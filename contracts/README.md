# Contract `app-updater/1` — Version 1.0.0

Single source of truth for the private in-app update system across Molly's applications (`Flutter` and `Android/Kotlin`), the Cloudflare Worker gateway, and Switchboard's `VersionProbe` / `publish_apk` integration.

## 1. Storage Layout in Cloudflare R2 (`private-app-releases`)

Files are keyed by the Android `applicationId` (`appId`):

```text
private-app-releases/
├── com.molly.switchboard/
│   ├── version.json
│   └── builds/
│       └── Switchboard-v0.34.0.apk
├── com.molly.pikminfilter/
│   ├── version.json
│   └── builds/
│       └── PikminFilter-v0.2.0.apk
└── ...
```

## 2. Manifest Schema (`contracts/version-manifest.schema.json`)

Every `build-apk.ps1` release build generates `dist/version.json` matching `version-manifest.schema.json`. When `publish-release.ps1` uploads the APK to R2, it writes `<appId>/version.json` to the bucket.

## 3. Cloudflare Worker Endpoints

1. **`GET /api/v1/version/:appId` (Open, read-only metadata for Switchboard `VersionProbe`)**
   - Requires no auth token; returns no download URL and no storage keys.
   - Response (`200 OK`):
     ```json
     {
       "appId": "com.molly.pikminfilter",
       "project": "PikminFilter",
       "version": "0.2.0",
       "versionName": "0.2.0",
       "versionCode": 2,
       "releaseDate": "2026-10-20T08:00:00Z"
     }
     ```
2. **`GET /api/v1/update/:appId` (Authenticated client check)**
   - Header: `Authorization: Bearer <SHARED_UPDATE_TOKEN>` (single token across Molly's apps, D-0002).
   - Response (`200 OK`): full `version.json` object plus a short-lived HMAC-signed `downloadUrl` (default TTL 900 seconds).
3. **`GET /api/v1/download?key=...&expires=...&sig=...` (Signed binary stream)**
   - Verifies expiration and HMAC-SHA256 signature (`${apkKey}:${expires}`), then streams the APK from R2 with `Content-Type: application/vnd.android.package-archive`.

## 4. Version History
- **1.0.0 (2026-10-20):** Initial `app-updater/1` manifest schema and Worker API specification.
