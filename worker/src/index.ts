export interface R2ObjectBodyLike {
  body: ReadableStream | Uint8Array | string | null;
  size: number;
  httpEtag: string;
  json<T = unknown>(): Promise<T>;
  writeHttpMetadata(headers: Headers): void;
}

export interface R2BucketLike {
  get(key: string): Promise<R2ObjectBodyLike | null>;
}

export interface Env {
  RELEASES_BUCKET: R2BucketLike;
  /** Single shared Bearer token across Molly's private client apps (D-0002). */
  APP_UPDATER_TOKEN: string;
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

const APP_ID_PATTERN = /^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z0-9_]+)+$/;

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store, no-cache, must-revalidate",
    },
  });
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

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    // Health check
    if (url.pathname === "/health" && request.method === "GET") {
      return jsonResponse({ status: "ok", schema: "app-updater/1" });
    }

    // 1. Open read-only version metadata for Switchboard VersionProbe
    // GET /api/v1/version/:appId
    if (url.pathname.startsWith("/api/v1/version/") && request.method === "GET") {
      const appId = decodeURIComponent(url.pathname.slice("/api/v1/version/".length));
      if (!appId || !APP_ID_PATTERN.test(appId)) {
        return jsonResponse({ error: "Invalid appId" }, 400);
      }

      const manifestObj = await env.RELEASES_BUCKET.get(`${appId}/version.json`);
      if (!manifestObj) {
        return jsonResponse({ error: "App manifest not found" }, 404);
      }

      const manifest = await manifestObj.json<AppReleaseManifest>();
      return jsonResponse({
        schema: manifest.schema || "app-updater/1",
        appId: manifest.appId,
        project: manifest.project,
        version: manifest.versionName,
        versionName: manifest.versionName,
        versionCode: manifest.versionCode,
        releaseDate: manifest.releaseDate,
      });
    }

    // 2. Authenticated Client Update Check
    // GET /api/v1/update/:appId
    if (url.pathname.startsWith("/api/v1/update/") && request.method === "GET") {
      const appId = decodeURIComponent(url.pathname.slice("/api/v1/update/".length));
      if (!appId || !APP_ID_PATTERN.test(appId)) {
        return jsonResponse({ error: "Invalid appId" }, 400);
      }

      const token = extractBearerToken(request);
      if (!env.APP_UPDATER_TOKEN || !token || !timingSafeEqualStr(token, env.APP_UPDATER_TOKEN)) {
        return jsonResponse({ error: "Forbidden" }, 403);
      }

      const manifestObj = await env.RELEASES_BUCKET.get(`${appId}/version.json`);
      if (!manifestObj) {
        return jsonResponse({ error: "App manifest not found" }, 404);
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

    // 3. Download APK via HMAC-Signed URL
    // GET /api/v1/download?key=...&expires=...&sig=...
    if (url.pathname === "/api/v1/download" && request.method === "GET") {
      const apkKey = url.searchParams.get("key") || "";
      const expiresStr = url.searchParams.get("expires") || "";
      const sig = url.searchParams.get("sig") || "";
      const expires = Number(expiresStr);

      if (
        !apkKey ||
        apkKey.includes("..") ||
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

      const apkObject = await env.RELEASES_BUCKET.get(apkKey);
      if (!apkObject || apkObject.body === null) {
        return new Response("APK file not found", { status: 404 });
      }

      const headers = new Headers();
      apkObject.writeHttpMetadata(headers);
      headers.set("Content-Type", "application/vnd.android.package-archive");
      headers.set("Content-Length", apkObject.size.toString());
      if (apkObject.httpEtag) {
        headers.set("ETag", apkObject.httpEtag);
      }

      return new Response(apkObject.body as BodyInit, { headers });
    }

    return new Response("Not Found", { status: 404 });
  },
};
