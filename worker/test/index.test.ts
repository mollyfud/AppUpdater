import assert from "node:assert/strict";
import { describe, it } from "node:test";
import worker, { type Env, type R2BucketLike, type R2ObjectBodyLike } from "../src/index.ts";
import * as workerModule from "../src/index.ts";

const SAMPLE_MANIFEST = {
  schema: "app-updater/1",
  appId: "com.molly.pikminfilter",
  project: "PikminFilter",
  versionName: "1.3.0",
  versionCode: 14,
  minRequiredVersionCode: 12,
  releaseDate: "2026-10-20T08:00:00Z",
  releaseNotes: "â€¢ Added offline caching\nâ€¢ Fixed sync timeout",
  apkKey: "com.molly.pikminfilter/builds/PikminFilter-v1.3.0.apk",
  sha256: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  fileSize: 12,
};

function makeFakeR2(files: Record<string, string | Uint8Array>): R2BucketLike {
  return {
    async get(key: string): Promise<R2ObjectBodyLike | null> {
      const val = files[key];
      if (val === undefined) {
        return null;
      }
      const bytes = typeof val === "string" ? new TextEncoder().encode(val) : val;
      return {
        body: bytes,
        size: bytes.byteLength,
        httpEtag: '"etag-123"',
        async json<T>() {
          return JSON.parse(new TextDecoder().decode(bytes)) as T;
        },
        writeHttpMetadata(headers: Headers) {
          headers.set("X-R2-Mock", "true");
        },
      };
    },
    async put(key: string, value: string) {
      files[key] = value;
      return {};
    },
    async list(options?: { prefix?: string; delimiter?: string }) {
      const prefix = options?.prefix || "";
      const keys = Object.keys(files).filter((k) => k.startsWith(prefix)).sort();
      if (!options?.delimiter) {
        return { objects: keys.map((key) => ({ key })), delimitedPrefixes: [], truncated: false };
      }
      const prefixes = new Set<string>();
      const objects: { key: string }[] = [];
      for (const k of keys) {
        const rest = k.slice(prefix.length);
        const i = rest.indexOf(options.delimiter);
        if (i >= 0) prefixes.add(prefix + rest.slice(0, i + 1));
        else objects.push({ key: k });
      }
      return { objects, delimitedPrefixes: [...prefixes], truncated: false };
    },
  };
}

const OTHER_MANIFEST = {
  ...SAMPLE_MANIFEST,
  appId: "com.molly.secretapp",
  project: "SecretApp",
  apkKey: "com.molly.secretapp/builds/SecretApp-v1.0.0.apk",
};

function makeEnv(extra: Record<string, string> = {}): Env & { files: Record<string, string | Uint8Array> } {
  const files: Record<string, string | Uint8Array> = {
    "com.molly.pikminfilter/version.json": JSON.stringify(SAMPLE_MANIFEST),
    "com.molly.pikminfilter/builds/PikminFilter-v1.3.0.apk": "FAKE_APK_DATA",
    "com.molly.secretapp/version.json": JSON.stringify(OTHER_MANIFEST),
    "com.molly.secretapp/builds/SecretApp-v1.0.0.apk": "SECRET_APK",
    ...extra,
  };
  return {
    files,
    RELEASES_BUCKET: makeFakeR2(files),
    APP_UPDATER_TOKEN: "secret-shared-token-123",
    APP_UPDATER_ADMIN_TOKEN: "admin-token-456",
    HMAC_SECRET: "hmac-signing-secret-xyz",
    TOKEN_TTL_SECONDS: "900",
  };
}

const BASE = "https://updater.example.com";

function get(path: string, token?: string): Request {
  return new Request(BASE + path, token ? { headers: { Authorization: `Bearer ${token}` } } : {});
}

function send(method: string, path: string, body: unknown, token = "admin-token-456"): Request {
  return new Request(BASE + path, {
    method,
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

async function createGrant(env: Env, body: unknown): Promise<Record<string, any>> {
  const res = await worker.fetch(send("POST", "/api/v1/admin/grants", body), env);
  assert.equal(res.status, 201);
  return (await res.json()) as Record<string, any>;
}

async function shareApp(env: Env, appId: string, shareable = true, title?: string): Promise<void> {
  const res = await worker.fetch(send("PUT", `/api/v1/admin/listing/${appId}`, { shareable, title }), env);
  assert.equal(res.status, 200);
}

describe("AppUpdater Cloudflare Worker Gateway", () => {
  it("GET /api/v1/version/:appId returns open read-only metadata for Switchboard VersionProbe without downloadUrl", async () => {
    const env = makeEnv();
    const req = new Request("https://updater.example.com/api/v1/version/com.molly.pikminfilter");
    const res = await worker.fetch(req, env);
    assert.equal(res.status, 200);
    assert.equal(res.headers.get("Access-Control-Allow-Origin"), "*");
    const body = (await res.json()) as Record<string, unknown>;
    assert.equal(body.version, "1.3.0");
    assert.equal(body.versionName, "1.3.0");
    assert.equal(body.versionCode, 14);
    assert.equal(body.project, "PikminFilter");
    assert.equal("downloadUrl" in body, false);
    assert.equal("apkKey" in body, false);

    // OPTIONS preflight check
    const optionsReq = new Request("https://updater.example.com/api/v1/version/com.molly.pikminfilter", {
      method: "OPTIONS",
    });
    const optionsRes = await worker.fetch(optionsReq, env);
    assert.equal(optionsRes.status, 204);
    assert.equal(optionsRes.headers.get("Access-Control-Allow-Origin"), "*");
  });

  it("GET /api/v1/update/:appId rejects missing or wrong Bearer token with 403", async () => {
    const env = makeEnv();
    const reqNoAuth = new Request("https://updater.example.com/api/v1/update/com.molly.pikminfilter");
    const resNoAuth = await worker.fetch(reqNoAuth, env);
    assert.equal(resNoAuth.status, 403);

    const reqBadAuth = new Request("https://updater.example.com/api/v1/update/com.molly.pikminfilter", {
      headers: { Authorization: "Bearer wrong-token" },
    });
    const resBadAuth = await worker.fetch(reqBadAuth, env);
    assert.equal(resBadAuth.status, 403);
  });

  it("GET /api/v1/update/:appId returns manifest with valid signed downloadUrl that streams APK from /api/v1/download", async () => {
    const env = makeEnv();
    const req = new Request("https://updater.example.com/api/v1/update/com.molly.pikminfilter", {
      headers: { Authorization: "Bearer secret-shared-token-123" },
    });
    const res = await worker.fetch(req, env);
    assert.equal(res.status, 200);
    const data = (await res.json()) as Record<string, unknown>;
    assert.equal(data.versionName, "1.3.0");
    assert.equal(typeof data.downloadUrl, "string");

    // Fetch the signed downloadUrl
    const dlRes = await worker.fetch(new Request(data.downloadUrl as string), env);
    assert.equal(dlRes.status, 200);
    assert.equal(dlRes.headers.get("Content-Type"), "application/vnd.android.package-archive");
    const apkText = await dlRes.text();
    assert.equal(apkText, "FAKE_APK_DATA");
  });

  it("GET /api/v1/download rejects tampered signature or expired timestamp with 403", async () => {
    const env = makeEnv();
    const reqTampered = new Request(
      "https://updater.example.com/api/v1/download?key=com.molly.pikminfilter%2Fbuilds%2FPikminFilter-v1.3.0.apk&expires=9999999999&sig=deadbeef"
    );
    const resTampered = await worker.fetch(reqTampered, env);
    assert.equal(resTampered.status, 403);
  });
});

describe("Per-person access grants (contract 1.1.0)", () => {
  it("admin API rejects missing, wrong or owner tokens, and is disabled without an admin secret", async () => {
    const env = makeEnv();
    const body = { name: "Sam", apps: ["com.molly.pikminfilter"] };
    assert.equal((await worker.fetch(send("POST", "/api/v1/admin/grants", body, "nope"), env)).status, 403);
    assert.equal(
      (await worker.fetch(send("POST", "/api/v1/admin/grants", body, "secret-shared-token-123"), env)).status,
      403
    );
    const noAdmin = { ...makeEnv(), APP_UPDATER_ADMIN_TOKEN: undefined };
    assert.equal((await worker.fetch(send("POST", "/api/v1/admin/grants", body), noAdmin)).status, 403);
  });

  it("creating a grant stores only the token hash and returns the token once with an invite link", async () => {
    const env = makeEnv();
    const created = await createGrant(env, { name: "Sam", apps: ["com.molly.pikminfilter"], days: 30 });
    assert.match(created.token, /^aug_[A-Za-z0-9_-]{43}$/);
    assert.equal(created.inviteUrl, `${BASE}/store#t=${created.token}`);
    assert.equal(created.grant.name, "Sam");
    assert.ok(Date.parse(created.grant.expires) > Date.now() + 29 * 86_400_000);
    // Not shareable yet -> a warning
    assert.ok(created.warnings.some((w: string) => w.includes("not marked shareable")));

    const grantKeys = Object.keys(env.files).filter((k) => k.startsWith("_grants/"));
    assert.equal(grantKeys.length, 1);
    assert.match(grantKeys[0], new RegExp(`^_grants/${created.grant.id}[a-f0-9]{48}\\.json$`));
    assert.equal(String(env.files[grantKeys[0]]).includes(created.token), false);
  });

  it("rejects invalid grant bodies with 400", async () => {
    const env = makeEnv();
    for (const body of [
      { apps: ["com.molly.pikminfilter"] },
      { name: "Sam", apps: [] },
      { name: "Sam", apps: ["../etc"] },
      { name: "Sam", apps: ["com.molly.pikminfilter"], days: 0 },
      { name: "Sam", apps: ["com.molly.pikminfilter"], days: 1.5 },
    ]) {
      assert.equal((await worker.fetch(send("POST", "/api/v1/admin/grants", body), env)).status, 400);
    }
  });

  it("a grant can update only shareable apps on its list; others look like missing apps (404)", async () => {
    const env = makeEnv();
    const { token } = await createGrant(env, { name: "Sam", apps: ["com.molly.pikminfilter"] });

    // Listed but not shareable yet -> 404
    assert.equal((await worker.fetch(get("/api/v1/update/com.molly.pikminfilter", token), env)).status, 404);

    await shareApp(env, "com.molly.pikminfilter");
    const res = await worker.fetch(get("/api/v1/update/com.molly.pikminfilter", token), env);
    assert.equal(res.status, 200);
    const data = (await res.json()) as Record<string, unknown>;
    const dl = await worker.fetch(new Request(data.downloadUrl as string), env);
    assert.equal(await dl.text(), "FAKE_APK_DATA");
    assert.equal(dl.headers.get("Content-Disposition"), 'attachment; filename="PikminFilter-v1.3.0.apk"');

    // Shareable but not on Sam's list -> 404, same body as an unknown app
    await shareApp(env, "com.molly.secretapp");
    const other = await worker.fetch(get("/api/v1/update/com.molly.secretapp", token), env);
    assert.equal(other.status, 404);
    assert.deepEqual(await other.json(), { error: "App manifest not found" });
  });

  it("apps [*] covers every shareable app, still not unshared ones", async () => {
    const env = makeEnv();
    const { token } = await createGrant(env, { name: "Family", apps: ["*"] });
    await shareApp(env, "com.molly.pikminfilter");
    assert.equal((await worker.fetch(get("/api/v1/update/com.molly.pikminfilter", token), env)).status, 200);
    assert.equal((await worker.fetch(get("/api/v1/update/com.molly.secretapp", token), env)).status, 404);
  });

  it("revoked, expired, unknown and malformed grant tokens get 403", async () => {
    const env = makeEnv();
    await shareApp(env, "com.molly.pikminfilter");
    const { token, grant } = await createGrant(env, { name: "Sam", apps: ["com.molly.pikminfilter"] });

    const revoked = await worker.fetch(send("POST", `/api/v1/admin/grants/${grant.id}/revoke`, {}), env);
    assert.equal(revoked.status, 200);
    assert.equal(((await revoked.json()) as any).grant.revoked, true);
    assert.equal((await worker.fetch(get("/api/v1/update/com.molly.pikminfilter", token), env)).status, 403);

    const second = await createGrant(env, { name: "Old", apps: ["com.molly.pikminfilter"] });
    const key = Object.keys(env.files).find((k) => k.startsWith(`_grants/${second.grant.id}`))!;
    env.files[key] = JSON.stringify({ ...second.grant, expires: "2020-01-01T00:00:00Z" });
    assert.equal((await worker.fetch(get("/api/v1/update/com.molly.pikminfilter", second.token), env)).status, 403);

    assert.equal(
      (await worker.fetch(get("/api/v1/update/com.molly.pikminfilter", "aug_" + "x".repeat(43)), env)).status,
      403
    );
    assert.equal((await worker.fetch(get("/api/v1/update/com.molly.pikminfilter", "aug_../../x"), env)).status, 403);
  });

  it("revoke validates the id and reports unknown grants", async () => {
    const env = makeEnv();
    assert.equal((await worker.fetch(send("POST", "/api/v1/admin/grants/xyz/revoke", {}), env)).status, 400);
    assert.equal(
      (await worker.fetch(send("POST", "/api/v1/admin/grants/0123456789abcdef/revoke", {}), env)).status,
      404
    );
  });

  it("lists grants without tokens and with a live flag", async () => {
    const env = makeEnv();
    const a = await createGrant(env, { name: "Sam", apps: ["com.molly.pikminfilter"], note: "tennis" });
    await createGrant(env, { name: "Alex", apps: ["*"] });
    await worker.fetch(send("POST", `/api/v1/admin/grants/${a.grant.id}/revoke`, {}), env);
    const res = await worker.fetch(get("/api/v1/admin/grants", "admin-token-456"), env);
    assert.equal(res.status, 200);
    const text = await res.text();
    assert.equal(text.includes(a.token), false);
    const { grants } = JSON.parse(text) as { grants: any[] };
    assert.equal(grants.length, 2);
    const sam = grants.find((g) => g.name === "Sam");
    assert.equal(sam.live, false);
    assert.equal(sam.note, "tennis");
    assert.equal(grants.find((g) => g.name === "Alex").live, true);
  });

  it("listing PUT validates input and warns when no release exists", async () => {
    const env = makeEnv();
    assert.equal((await worker.fetch(send("PUT", "/api/v1/admin/listing/com.molly.pikminfilter", {}), env)).status, 400);
    assert.equal(
      (await worker.fetch(send("PUT", "/api/v1/admin/listing/_grants", { shareable: true }), env)).status,
      400
    );
    const res = await worker.fetch(send("PUT", "/api/v1/admin/listing/com.molly.newapp", { shareable: true }), env);
    assert.equal(res.status, 200);
    const body = (await res.json()) as any;
    assert.deepEqual(body.warnings, ["com.molly.newapp: no release published yet"]);
  });
});

describe("Catalog and store page", () => {
  it("catalog needs a valid token", async () => {
    const env = makeEnv();
    assert.equal((await worker.fetch(get("/api/v1/catalog"), env)).status, 403);
    assert.equal((await worker.fetch(get("/api/v1/catalog", "wrong"), env)).status, 403);
  });

  it("owner catalog lists every app with its shareable flag and never lists _grants", async () => {
    const env = makeEnv();
    await createGrant(env, { name: "Sam", apps: ["*"] });
    await shareApp(env, "com.molly.pikminfilter", true, "Pikmin Filter");
    const res = await worker.fetch(get("/api/v1/catalog", "secret-shared-token-123"), env);
    const body = (await res.json()) as any;
    assert.equal(body.viewer, null);
    assert.deepEqual(
      body.apps.map((a: any) => [a.appId, a.title, a.shareable]),
      [
        ["com.molly.pikminfilter", "Pikmin Filter", true],
        ["com.molly.secretapp", "SecretApp", false],
      ]
    );
    assert.equal("downloadUrl" in body.apps[0], false);
    assert.equal("apkKey" in body.apps[0], false);

    const admin = await worker.fetch(get("/api/v1/admin/apps", "admin-token-456"), env);
    assert.deepEqual(await admin.json(), body);
    assert.equal((await worker.fetch(get("/api/v1/admin/apps", "secret-shared-token-123"), env)).status, 403);
  });

  it("grant catalog lists only shared apps on its list, with the viewer name", async () => {
    const env = makeEnv();
    await shareApp(env, "com.molly.pikminfilter", true);
    const { token } = await createGrant(env, {
      name: "Sam",
      apps: ["com.molly.pikminfilter", "com.molly.secretapp", "com.molly.notpublished"],
    });
    const body = (await (await worker.fetch(get("/api/v1/catalog", token), env)).json()) as any;
    assert.equal(body.viewer, "Sam");
    assert.deepEqual(
      body.apps.map((a: any) => a.appId),
      ["com.molly.pikminfilter"]
    );
    assert.equal("shareable" in body.apps[0], false);
  });

  it("serves the store page and script with strict security headers; / redirects to /store", async () => {
    const env = makeEnv();
    const page = await worker.fetch(get("/store"), env);
    assert.equal(page.status, 200);
    assert.match(page.headers.get("Content-Type") || "", /^text\/html/);
    const csp = page.headers.get("Content-Security-Policy") || "";
    assert.match(csp, /script-src 'self'/);
    assert.match(csp, /frame-ancestors 'none'/);
    assert.equal(page.headers.get("Referrer-Policy"), "no-referrer");
    const html = await page.text();
    assert.match(html, /<script src="\/store\.js"><\/script>/);
    assert.equal(/<script>/.test(html), false);

    const js = await worker.fetch(get("/store.js"), env);
    assert.match(js.headers.get("Content-Type") || "", /^text\/javascript/);
    const code = await js.text();
    assert.match(code, /history\.replaceState/);
    assert.equal(code.includes("innerHTML"), false);
    assert.doesNotThrow(() => new Function(code));

    const root = await worker.fetch(get("/"), env);
    assert.equal(root.status, 302);
    assert.equal(root.headers.get("Location"), `${BASE}/store`);
  });

  it("main module exports only functions (workerd refuses to start on other named exports)", () => {
    for (const [name, value] of Object.entries(workerModule)) {
      if (name === "default") continue;
      assert.equal(typeof value, "function", `export ${name} must be a function or moved to another module`);
    }
  });

  it("health reports the worker version", async () => {
    const body = (await (await worker.fetch(get("/health"), makeEnv())).json()) as any;
    assert.equal(body.worker, "0.2.0");
  });
});
