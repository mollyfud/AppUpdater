import {
  GRANT_PREFIX,
  grantCovers,
  grantKeyForHash,
  isGrantLive,
  looksLikeGrantToken,
  newGrantToken,
  sha256Hex,
  type AccessGrant,
  type StoreListing,
} from "./access.ts";
import { STORE_HTML, STORE_JS, STORE_SECURITY_HEADERS } from "./store-page.ts";
import { WORKER_VERSION } from "./version.ts";

export interface R2ObjectBodyLike {
  body: ReadableStream | Uint8Array | string | null;
  size: number;
  httpEtag: string;
  json<T = unknown>(): Promise<T>;
  writeHttpMetadata(headers: Headers): void;
}

export interface R2ListResultLike {
  objects: { key: string }[];
  delimitedPrefixes: string[];
  truncated: boolean;
  cursor?: string;
}

export interface R2BucketLike {
  get(key: string, options?: { range?: Headers | unknown }): Promise<R2ObjectBodyLike | null>;
  put(key: string, value: string, options?: { httpMetadata?: { contentType?: string } }): Promise<unknown>;
  list(options?: { prefix?: string; delimiter?: string; cursor?: string }): Promise<R2ListResultLike>;
}

export interface Env {
  RELEASES_BUCKET: R2BucketLike;
  /** Owner (master) Bearer token on Molly's own devices (D-0002, kept by D-0009). Sees every app. */
  APP_UPDATER_TOKEN: string;
  /** Admin token for /api/v1/admin/* (grants, listings). Unset = admin API disabled. */
  APP_UPDATER_ADMIN_TOKEN?: string;
  /** Secret key used to HMAC-SHA256 sign short-lived APK download URLs. */
  HMAC_SECRET: string;
  /** Download link TTL in seconds (default: "900" = 15 minutes). */
  TOKEN_TTL_SECONDS?: string;
}

export interface AppReleaseManifest {
  schema: string;
  appId: string;
  project: string;
  versionName: string;
  versionCode: number;
  minRequiredVersionCode: number;
  releaseDate: string;
  releaseNotes: string;
  apkKey: string;
  sha256: string;
  fileSize: number;
  downloadUrl?: string;
  artifacts?: Record<
    string,
    {
      key: string;
      sha256: string;
      fileSize: number;
      downloadUrl?: string;
    }
  >;
}

type Viewer = { kind: "owner" } | { kind: "grant"; grant: AccessGrant };

const APP_ID_PATTERN = /^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z0-9_]+)+$/;
const GRANT_ID_PATTERN = /^[a-f0-9]{16}$/;

function jsonResponse(body: unknown, status = 200, extraHeaders?: Record<string, string>): Response {
  const headers = new Headers({
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store, no-cache, must-revalidate",
  });
  if (extraHeaders) {
    for (const [k, v] of Object.entries(extraHeaders)) {
      headers.set(k, v);
    }
  }
  return new Response(JSON.stringify(body), {
    status,
    headers,
  });
}

function notFoundManifest(): Response {
  return jsonResponse({ error: "App manifest not found" }, 404);
}

/**
 * Constant-time string comparison to prevent timing side-channel attacks on tokens/signatures.
 */
export function timingSafeEqualStr(a: string, b: string): boolean {
  const enc = new TextEncoder();
  const aBytes = enc.encode(a);
  const bBytes = enc.encode(b);
  if (aBytes.length !== bBytes.length || aBytes.length === 0) {
    return false;
  }
  let diff = 0;
  for (let i = 0; i < aBytes.length; i++) {
    diff |= aBytes[i] ^ bBytes[i];
  }
  return diff === 0;
}

export async function signPayload(data: string, secret: string): Promise<string> {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const signature = await crypto.subtle.sign("HMAC", key, encoder.encode(data));
  return Array.from(new Uint8Array(signature))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function extractBearerToken(request: Request): string {
  const authHeader = request.headers.get("Authorization") || "";
  if (!authHeader.startsWith("Bearer ")) {
    return "";
  }
  return authHeader.slice("Bearer ".length).trim();
}

/** Owner token, or a live per-person grant; null = not allowed. */
async function resolveViewer(request: Request, env: Env): Promise<Viewer | null> {
  const token = extractBearerToken(request);
  if (!token) return null;
  if (env.APP_UPDATER_TOKEN && timingSafeEqualStr(token, env.APP_UPDATER_TOKEN)) {
    return { kind: "owner" };
  }
  if (!looksLikeGrantToken(token)) return null;
  const obj = await env.RELEASES_BUCKET.get(grantKeyForHash(await sha256Hex(token)));
  if (!obj) return null;
  const grant = await obj.json<AccessGrant>();
  return isGrantLive(grant) ? { kind: "grant", grant } : null;
}

function isAdmin(request: Request, env: Env): boolean {
  const token = extractBearerToken(request);
  return !!env.APP_UPDATER_ADMIN_TOKEN && !!token && timingSafeEqualStr(token, env.APP_UPDATER_ADMIN_TOKEN);
}

async function readJson<T>(env: Env, key: string): Promise<T | null> {
  const obj = await env.RELEASES_BUCKET.get(key);
  return obj ? obj.json<T>() : null;
}

function readListing(env: Env, appId: string): Promise<StoreListing | null> {
  return readJson<StoreListing>(env, `${appId}/listing.json`);
}

/** Owner sees everything; a grant needs the app in its list AND the app's listing marked shareable. */
async function viewerCanSee(env: Env, viewer: Viewer, appId: string): Promise<boolean> {
  if (viewer.kind === "owner") return true;
  if (!grantCovers(viewer.grant, appId)) return false;
  const listing = await readListing(env, appId);
  return listing?.shareable === true;
}

async function listAll(env: Env, prefix: string, delimiter?: string): Promise<R2ListResultLike> {
  const out: R2ListResultLike = { objects: [], delimitedPrefixes: [], truncated: false };
  let cursor: string | undefined;
  do {
    const page = await env.RELEASES_BUCKET.list({ prefix, delimiter, cursor });
    out.objects.push(...page.objects);
    out.delimitedPrefixes.push(...(page.delimitedPrefixes || []));
    cursor = page.truncated ? page.cursor : undefined;
  } while (cursor);
  return out;
}

async function listAppIds(env: Env): Promise<string[]> {
  const res = await listAll(env, "", "/");
  return res.delimitedPrefixes.map((p) => p.replace(/\/$/, "")).filter((id) => APP_ID_PATTERN.test(id));
}

async function listGrants(env: Env): Promise<{ key: string; grant: AccessGrant }[]> {
  const res = await listAll(env, GRANT_PREFIX);
  const items = await Promise.all(
    res.objects.map(async (obj) => {
      const grant = await readJson<AccessGrant>(env, obj.key);
      return grant ? { key: obj.key, grant } : null;
    })
  );
  return items.filter((g): g is NonNullable<typeof g> => g !== null);
}

async function buildCatalog(env: Env, viewer: Viewer) {
  const candidates =
    viewer.kind === "owner" || viewer.grant.apps.includes("*") ? await listAppIds(env) : viewer.grant.apps;
  const appPromises = candidates.map(async (appId) => {
    const [manifest, listing] = await Promise.all([
      readJson<AppReleaseManifest>(env, `${appId}/version.json`),
      readListing(env, appId),
    ]);
    if (!manifest) return null;
    const shareable = listing?.shareable === true;
    if (viewer.kind === "grant" && !shareable) return null;
    return {
      appId,
      title: listing?.title || manifest.project || appId,
      summary: listing?.summary || "",
      versionName: manifest.versionName,
      versionCode: manifest.versionCode,
      releaseDate: manifest.releaseDate,
      releaseNotes: manifest.releaseNotes,
      fileSize: manifest.fileSize,
      sha256: manifest.sha256,
      ...(viewer.kind === "owner" ? { shareable } : {}),
    };
  });
  const resolved = await Promise.all(appPromises);
  const apps = resolved.filter((a): a is NonNullable<typeof a> => a !== null);
  apps.sort((a, b) => a.title.localeCompare(b.title));
  return { viewer: viewer.kind === "grant" ? viewer.grant.name : null, apps };
}

async function parseBody(request: Request): Promise<Record<string, unknown> | null> {
  try {
    const body = await request.json();
    return body && typeof body === "object" && !Array.isArray(body) ? (body as Record<string, unknown>) : null;
  } catch {
    return null;
  }
}

function optionalText(value: unknown, max: number): string | undefined | false {
  if (value === undefined || value === null || value === "") return undefined;
  if (typeof value !== "string" || value.length > max) return false;
  return value.trim();
}

function storeResponse(body: string, contentType: string): Response {
  const headers = new Headers(STORE_SECURITY_HEADERS);
  headers.set("Content-Type", contentType);
  return new Response(body, { headers });
}

async function handleAdmin(request: Request, env: Env, url: URL): Promise<Response> {
  if (!isAdmin(request, env)) {
    return jsonResponse({ error: "Forbidden" }, 403);
  }
  const path = url.pathname.slice("/api/v1/admin/".length);

  // GET /api/v1/admin/apps - every published app with its listing (owner view of the catalog)
  if (path === "apps" && request.method === "GET") {
    return jsonResponse(await buildCatalog(env, { kind: "owner" }));
  }

  // GET /api/v1/admin/grants - every grant (no tokens; they are never stored)
  if (path === "grants" && request.method === "GET") {
    const grants = (await listGrants(env)).map((g) => ({ ...g.grant, live: isGrantLive(g.grant) }));
    grants.sort((a, b) => a.created.localeCompare(b.created));
    return jsonResponse({ grants });
  }

  // POST /api/v1/admin/grants {name, apps, days?, note?} - returns the token ONCE
  if (path === "grants" && request.method === "POST") {
    const body = await parseBody(request);
    if (!body) return jsonResponse({ error: "Body must be a JSON object" }, 400);
    const name = optionalText(body.name, 60);
    if (!name) return jsonResponse({ error: "name is required (1-60 chars)" }, 400);
    const note = optionalText(body.note, 200);
    if (note === false) return jsonResponse({ error: "note must be text up to 200 chars" }, 400);
    const apps = body.apps;
    if (
      !Array.isArray(apps) ||
      apps.length === 0 ||
      apps.length > 50 ||
      !apps.every((a) => typeof a === "string" && (a === "*" || APP_ID_PATTERN.test(a)))
    ) {
      return jsonResponse({ error: 'apps must be a non-empty list of appIds or ["*"]' }, 400);
    }
    let expires: string | undefined;
    if (body.days !== undefined && body.days !== null) {
      const days = Number(body.days);
      if (!Number.isInteger(days) || days < 1 || days > 3650) {
        return jsonResponse({ error: "days must be a whole number from 1 to 3650" }, 400);
      }
      expires = new Date(Date.now() + days * 86_400_000).toISOString();
    }

    const token = newGrantToken();
    const hash = await sha256Hex(token);
    const grant: AccessGrant = {
      id: hash.slice(0, 16),
      name,
      apps: [...new Set(apps as string[])],
      created: new Date().toISOString(),
      revoked: false,
      ...(expires ? { expires } : {}),
      ...(note ? { note } : {}),
    };
    await env.RELEASES_BUCKET.put(grantKeyForHash(hash), JSON.stringify(grant, null, 2), {
      httpMetadata: { contentType: "application/json" },
    });

    const warnings: string[] = [];
    for (const appId of grant.apps.filter((a) => a !== "*")) {
      if (!(await readJson(env, `${appId}/version.json`))) {
        warnings.push(`${appId}: no release published yet`);
      }
      const listing = await readListing(env, appId);
      if (listing?.shareable !== true) {
        warnings.push(`${appId}: not marked shareable, so this person won't see it (run set-listing.ps1 -Shareable)`);
      }
    }
    return jsonResponse({ token, inviteUrl: `${url.origin}/store#t=${token}`, grant, warnings }, 201);
  }

  // POST /api/v1/admin/grants/:id/revoke
  const revoke = /^grants\/([^/]+)\/revoke$/.exec(path);
  if (revoke && request.method === "POST") {
    const id = revoke[1];
    if (!GRANT_ID_PATTERN.test(id)) return jsonResponse({ error: "Invalid grant id" }, 400);
    const res = await listAll(env, `${GRANT_PREFIX}${id}`);
    if (res.objects.length !== 1) return jsonResponse({ error: "Grant not found" }, 404);
    const key = res.objects[0].key;
    const grant = await readJson<AccessGrant>(env, key);
    if (!grant) return jsonResponse({ error: "Grant not found" }, 404);
    if (!grant.revoked) {
      grant.revoked = true;
      grant.revokedAt = new Date().toISOString();
      await env.RELEASES_BUCKET.put(key, JSON.stringify(grant, null, 2), {
        httpMetadata: { contentType: "application/json" },
      });
    }
    return jsonResponse({ grant });
  }

  // PUT /api/v1/admin/listing/:appId {shareable, title?, summary?}
  if (path.startsWith("listing/") && request.method === "PUT") {
    const appId = decodeURIComponent(path.slice("listing/".length));
    if (!APP_ID_PATTERN.test(appId)) return jsonResponse({ error: "Invalid appId" }, 400);
    const body = await parseBody(request);
    if (!body || typeof body.shareable !== "boolean") {
      return jsonResponse({ error: "shareable (true/false) is required" }, 400);
    }
    const title = optionalText(body.title, 80);
    const summary = optionalText(body.summary, 300);
    if (title === false || summary === false) {
      return jsonResponse({ error: "title (max 80) and summary (max 300) must be text" }, 400);
    }
    const listing: StoreListing = {
      appId,
      shareable: body.shareable,
      ...(title ? { title } : {}),
      ...(summary ? { summary } : {}),
      updated: new Date().toISOString(),
    };
    await env.RELEASES_BUCKET.put(`${appId}/listing.json`, JSON.stringify(listing, null, 2), {
      httpMetadata: { contentType: "application/json" },
    });
    const warnings = (await readJson(env, `${appId}/version.json`)) ? [] : [`${appId}: no release published yet`];
    return jsonResponse({ listing, warnings });
  }

  return jsonResponse({ error: "Unknown admin endpoint" }, 404);
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    // Health check
    if (url.pathname === "/health" && request.method === "GET") {
      return jsonResponse({ status: "ok", schema: "app-updater/1", worker: WORKER_VERSION });
    }

    // Store page (token-gated in the browser via /api/v1/catalog)
    if (request.method === "GET" && url.pathname === "/") {
      return Response.redirect(`${url.origin}/store`, 302);
    }
    if (request.method === "GET" && url.pathname === "/store") {
      return storeResponse(STORE_HTML, "text/html; charset=utf-8");
    }
    if (request.method === "GET" && url.pathname === "/store.js") {
      return storeResponse(STORE_JS, "text/javascript; charset=utf-8");
    }

    // 1. Open read-only version metadata for Switchboard VersionProbe (with open CORS for web hubs/dashboards)
    // OPTIONS & GET /api/v1/version/:appId
    if (url.pathname.startsWith("/api/v1/version/")) {
      const corsHeaders = {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "GET, HEAD, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type",
      };

      if (request.method === "OPTIONS") {
        return new Response(null, { status: 204, headers: corsHeaders });
      }

      if (request.method === "GET") {
        const appId = decodeURIComponent(url.pathname.slice("/api/v1/version/".length));
        if (!appId || !APP_ID_PATTERN.test(appId)) {
          return jsonResponse({ error: "Invalid appId" }, 400, corsHeaders);
        }

        const manifestObj = await env.RELEASES_BUCKET.get(`${appId}/version.json`);
        if (!manifestObj) {
          return jsonResponse({ error: "App manifest not found" }, 404, corsHeaders);
        }

        const manifest = await manifestObj.json<AppReleaseManifest>();
        return jsonResponse(
          {
            schema: manifest.schema || "app-updater/1",
            appId: manifest.appId,
            project: manifest.project,
            version: manifest.versionName,
            versionName: manifest.versionName,
            versionCode: manifest.versionCode,
            releaseDate: manifest.releaseDate,
          },
          200,
          corsHeaders
        );
      }
    }

    // 2. Authenticated Client Update Check (owner token or per-person grant)
    // GET /api/v1/update/:appId
    if (url.pathname.startsWith("/api/v1/update/") && request.method === "GET") {
      const appId = decodeURIComponent(url.pathname.slice("/api/v1/update/".length));
      if (!appId || !APP_ID_PATTERN.test(appId)) {
        return jsonResponse({ error: "Invalid appId" }, 400);
      }

      const viewer = await resolveViewer(request, env);
      if (!viewer) {
        return jsonResponse({ error: "Forbidden" }, 403);
      }
      // A grant gets the same 404 as an unknown app, so it can't probe which other apps exist.
      if (!(await viewerCanSee(env, viewer, appId))) {
        return notFoundManifest();
      }

      const manifestObj = await env.RELEASES_BUCKET.get(`${appId}/version.json`);
      if (!manifestObj) {
        return notFoundManifest();
      }

      const manifest = await manifestObj.json<AppReleaseManifest>();
      const ttl = Math.max(60, parseInt(env.TOKEN_TTL_SECONDS || "900", 10) || 900);
      const expires = Math.floor(Date.now() / 1000) + ttl;
      const signature = await signPayload(`${manifest.apkKey}:${expires}`, env.HMAC_SECRET);
      const downloadUrl = `${url.origin}/api/v1/download?key=${encodeURIComponent(manifest.apkKey)}&expires=${expires}&sig=${signature}`;

      return jsonResponse({
        ...manifest,
        downloadUrl,
      });
    }

    // 3. Catalog of the apps this token may install (store page)
    // GET /api/v1/catalog
    if (url.pathname === "/api/v1/catalog" && request.method === "GET") {
      const viewer = await resolveViewer(request, env);
      if (!viewer) {
        return jsonResponse({ error: "Forbidden" }, 403);
      }
      return jsonResponse(await buildCatalog(env, viewer));
    }

    // 4. Admin API (grants and listings), separate admin token
    if (url.pathname.startsWith("/api/v1/admin/")) {
      return handleAdmin(request, env, url);
    }

    // 5. Download APK via HMAC-Signed URL
    // GET /api/v1/download?key=...&expires=...&sig=...
    if (url.pathname === "/api/v1/download" && request.method === "GET") {
      const apkKey = url.searchParams.get("key") || "";
      const expiresStr = url.searchParams.get("expires") || "";
      const sig = url.searchParams.get("sig") || "";
      const expires = Number(expiresStr);

      if (
        !apkKey ||
        apkKey.includes("..") ||
        apkKey.startsWith("_") ||
        !Number.isFinite(expires) ||
        !sig ||
        Math.floor(Date.now() / 1000) > expires
      ) {
        return new Response("Download link expired or invalid", { status: 403 });
      }

      const expectedSig = await signPayload(`${apkKey}:${expires}`, env.HMAC_SECRET);
      if (!timingSafeEqualStr(sig, expectedSig)) {
        return new Response("Invalid signature", { status: 403 });
      }

      const rangeHeader = request.headers.get("Range");
      const apkObject = await env.RELEASES_BUCKET.get(
        apkKey,
        rangeHeader ? { range: request.headers } : undefined
      );
      if (!apkObject || apkObject.body === null) {
        return new Response("APK file not found", { status: 404 });
      }

      const headers = new Headers();
      apkObject.writeHttpMetadata(headers);
      headers.set("Content-Type", "application/vnd.android.package-archive");
      headers.set("Accept-Ranges", "bytes");
      const fileName = (apkKey.split("/").pop() || "app.apk").replace(/[^A-Za-z0-9._-]/g, "_");
      headers.set("Content-Disposition", `attachment; filename="${fileName}"`);
      if (apkObject.httpEtag) {
        headers.set("ETag", apkObject.httpEtag);
      }

      const isRange = Boolean(
        rangeHeader && "range" in apkObject && (apkObject as { range?: unknown }).range
      );
      const status = isRange ? 206 : 200;

      return new Response(apkObject.body as BodyInit, { status, headers });
    }

    return new Response("Not Found", { status: 404 });
  },
};
