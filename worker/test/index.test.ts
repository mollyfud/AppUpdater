import assert from "node:assert/strict";
import { describe, it } from "node:test";
import worker, { type Env, type R2BucketLike, type R2ObjectBodyLike } from "../src/index.ts";

const SAMPLE_MANIFEST = {
  schema: "app-updater/1",
  appId: "com.molly.pikminfilter",
  project: "PikminFilter",
  versionName: "1.3.0",
  versionCode: 14,
  minRequiredVersionCode: 12,
  releaseDate: "2026-10-20T08:00:00Z",
  releaseNotes: "• Added offline caching\n• Fixed sync timeout",
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
  };
}

function makeEnv(): Env {
  return {
    RELEASES_BUCKET: makeFakeR2({
      "com.molly.pikminfilter/version.json": JSON.stringify(SAMPLE_MANIFEST),
      "com.molly.pikminfilter/builds/PikminFilter-v1.3.0.apk": "FAKE_APK_DATA",
    }),
    APP_UPDATER_TOKEN: "secret-shared-token-123",
    HMAC_SECRET: "hmac-signing-secret-xyz",
    TOKEN_TTL_SECONDS: "900",
  };
}

describe("AppUpdater Cloudflare Worker Gateway", () => {
  it("GET /api/v1/version/:appId returns open read-only metadata for Switchboard VersionProbe without downloadUrl", async () => {
    const env = makeEnv();
    const req = new Request("https://updater.example.com/api/v1/version/com.molly.pikminfilter");
    const res = await worker.fetch(req, env);
    assert.equal(res.status, 200);
    const body = (await res.json()) as Record<string, unknown>;
    assert.equal(body.version, "1.3.0");
    assert.equal(body.versionName, "1.3.0");
    assert.equal(body.versionCode, 14);
    assert.equal(body.project, "PikminFilter");
    assert.equal("downloadUrl" in body, false);
    assert.equal("apkKey" in body, false);
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
