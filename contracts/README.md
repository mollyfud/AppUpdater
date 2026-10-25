# Contract `app-updater/1` — Version 1.1.0

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

Every `build-apk.ps1` release build generates `dist/version.json` matching `version-manifest.schema.json`. When `publish-release.ps1` uploads the APK to R2, it writes `<appId>/version.json` to the bucket. The publisher first checks the APK's package, versionCode and versionName against the manifest (`aapt2 dump badging`, so it needs Android build-tools) and refuses on a mismatch.

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
   - Header: `Authorization: Bearer <token>` - the owner token (D-0002) or a per-person grant token (section 4).
   - Response (`200 OK`): full `version.json` object plus a short-lived HMAC-signed `downloadUrl` (default TTL 900 seconds).
3. **`GET /api/v1/download?key=...&expires=...&sig=...` (Signed binary stream)**
   - Verifies expiration and HMAC-SHA256 signature (`${apkKey}:${expires}`), then streams the APK from R2 with `Content-Type: application/vnd.android.package-archive`.

## 4. Sharing: access grants, listings, catalog and store (1.1.0)

Additive; the manifest schema and every 1.0.0 endpoint behave as before for the owner token.
Design: `docs/design/sharing-and-store.md`.

### 4.1 Tokens
- **Owner token** (`APP_UPDATER_TOKEN`, D-0002/D-0009): Molly's own devices, sees every app.
- **Grant token** (`aug_` + 43 base64url chars): one per person, made by `scripts/grant-access.ps1`.
  The Worker stores only `sha256(token)`, at `_grants/<hex>.json` (`contracts/access-grant.schema.json`).
  A grant works only while not revoked and not past `expires`.
- **Admin token** (`APP_UPDATER_ADMIN_TOKEN`): only for `/api/v1/admin/*`. Unset = admin API off.
  Never put it in an app.

### 4.2 Store listing
`<appId>/listing.json` (`contracts/store-listing.schema.json`): `shareable`, optional `title`,
`summary`. Set with `scripts/set-listing.ps1`; `publish-release.ps1` never overwrites it.

### 4.3 Who may see an app
Owner: every app. Grant: the app is in the grant's `apps` (or `apps` is `["*"]`) **and** its listing
says `shareable: true`. Anything else gets the same `404 {"error":"App manifest not found"}` as an
unknown app, so a grant can't probe which other apps exist.

### 4.4 Endpoints
- `GET /api/v1/update/:appId` - now also accepts a grant token (rules in 4.3).
- `GET /api/v1/catalog` (owner or grant) - `{"viewer": "<grant name>"|null, "apps": [{appId, title,
  summary, versionName, versionCode, releaseDate, releaseNotes, fileSize, sha256, shareable?}]}`.
  No download links or storage keys; the store page calls `/update/:appId` for a fresh signed link.
  `shareable` only in the owner view.
- `GET /store`, `GET /store.js` - the store page (no auth to load; it asks for a token). Invite links
  are `/store#t=<token>`: the fragment is never sent to the server. `GET /` redirects to `/store`.
- `GET /api/v1/download` - unchanged, now also sends `Content-Disposition: attachment; filename=...`.
- `GET /health` - adds `"worker": "<version>"`.
- Admin (Bearer admin token):
  - `GET /api/v1/admin/apps` - the owner catalog.
  - `GET /api/v1/admin/grants` - every grant plus `live`; never tokens.
  - `POST /api/v1/admin/grants` `{name (1-60), apps, days? (1-3650), note? (<=200)}` -> `201
    {token, inviteUrl, grant, warnings}`. The token is returned only here.
  - `POST /api/v1/admin/grants/:id/revoke` (`id` = 16 hex chars) -> `{grant}`.
  - `PUT /api/v1/admin/listing/:appId` `{shareable, title? (<=80), summary? (<=300)}` -> `{listing, warnings}`.

## 5. Version History
- **1.1.0 (2026-10-21):** Per-person access grants, store listings, catalog, store page and admin API (section 4). Additive.
- **1.0.0 (2026-10-20):** Initial `app-updater/1` manifest schema and Worker API specification.
