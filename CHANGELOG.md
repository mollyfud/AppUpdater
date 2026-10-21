# Changelog

All notable changes to **AppUpdater** will be documented in this file.

## [worker 0.2.0, contract app-updater/1 1.1.0] - 2026-10-21
- **App sharing (D-0007..D-0009, `docs/design/sharing-and-store.md`):** per-person access grants. Each person gets their own `aug_...` token limited to a list of apps, with optional expiry, revocable on its own. The Worker stores only the token's SHA-256 at `_grants/<hash>.json` in the existing R2 bucket. The owner token (`APP_UPDATER_TOKEN`) works as before.
- Grants only reach apps marked shareable in `<appId>/listing.json`; any other app returns the same 404 as an unknown app.
- New `GET /api/v1/catalog`, token-gated store page at `GET /store` (+ `/store.js`, strict CSP, invite links carry the token in the URL fragment), `GET /` redirects there.
- New admin API under `/api/v1/admin/*` (apps, grants, revoke, listing) behind a separate secret `APP_UPDATER_ADMIN_TOKEN` (unset = admin API off).
- `/api/v1/download` sends `Content-Disposition: attachment` with the APK file name; `/health` reports `worker`.
- New scripts `scripts/grant-access.ps1`, `scripts/set-listing.ps1` (shared `scripts/updater-admin.ps1`); new schemas `contracts/access-grant.schema.json`, `contracts/store-listing.schema.json`. Manifest schema and both SDKs unchanged.
- Tests: 33 Worker tests (grants, revoke/expiry, catalog filtering, admin auth, store headers, palette 4.5:1 contrast in light and dark, main module exports only functions).
- Fixed before release: a non-function named export (`WORKER_VERSION`) from `src/index.ts` made workerd refuse to start; it lives in `src/version.ts`.

## [app_updater_flutter 0.3.0] - 2026-10-21
- **Fix (blocking):** the package now imports `package:material_ui/material_ui.dart` instead of `flutter/material.dart` (new dependency `material_ui: ^1.6.0`). On Flutter 3.47 Material lives in `material_ui` with its own `Theme` and `MaterialLocalizations`; the old import made `showDialog` throw "No MaterialLocalizations found" inside material_ui apps (no update dialog ever opened) and made the tile render with the default light theme in dark apps. **Apps on Flutter 3.47 must rebuild against this version.**
- `CheckForUpdateTile` and `UpdatePromptDialog.checkOnLaunch` now catch `showDialog` failures: the tile shows an error status and the failure is added to `lastCheckReport` (`dialog error: ...`); the launch check stays silent but logs it. New `UpdateService.recordDialogFailure`.
- Tests: material_ui `MaterialApp` light/dark tile + "Update Now" dialog test (also checks the tile follows the app theme), and a dialog-failure test.

## [app_updater_flutter 0.2.0] - 2026-10-20
- **Behaviour change:** HTTP 404 from `GET /api/v1/update/:appId` is now an `error`, not `upToDate`. The Worker's JSON 404 (`App manifest not found`) gives `Server has no release for <appId> (HTTP 404)`; any other 404 (e.g. the plain-text route 404) gives `Update endpoint not found at <endpoint> (HTTP 404) - check the gateway URL`.
- A newer build whose manifest has a `sha256` that isn't 64 chars or an empty `downloadUrl` is now an `error` ("... manifest is incomplete (sha256 length N, downloadUrl empty|ok)") instead of `upToDate`.
- `UpdateCheckResult` gains optional `appId`, `endpoint`, `httpStatus`, `remoteVersionCode`, `remoteVersionName`, `missingSettings` and a shared one-line `summary` (e.g. `Up to date (local v0.7.0 build 9, server v0.7.0 build 9, HTTP 200)`). Existing factory calls keep working.
- `UpdateService` keeps a token-free debug log of the last check (also sent to `debugPrint` with an `[app_updater]` prefix): new `lastCheckLog`, `lastCheckReport` and `lastResult`. The log never contains the token or the signed download URL (only its host); endpoints are logged without query strings.
- `CheckForUpdateTile` shows `result.summary` and, with `showDetails` (default `true`), a "Details" button that opens the last check's report in a selectable dialog.
- New `appUpdaterFlutterVersion` constant (`lib/src/update_service.dart`) reported in the log: bump it together with `pubspec.yaml`.

## [0.1.0] - 2026-10-20
- Initial project scaffolding (`C:\antigravity\AppUpdater`) and registration in `C:\antigravity\AGENTS.md`.
- Defined `app-updater/1` v1.0.0 contract (`contracts/version-manifest.schema.json` and `contracts/README.md`).
- Added architecture and implementation plan (`docs/DESIGN.md` and `docs/ai-notes/PLAN.md`) recording Molly's decisions (D-0001 to D-0004).
- **Phase 1 — Cloudflare Worker & Publisher Script:**
  - `worker/src/index.ts` + `wrangler.toml`: implements `GET /api/v1/version/:appId` (open version metadata for Switchboard `VersionProbe`), `GET /api/v1/update/:appId` (single shared Bearer token + 15-min HMAC-SHA256 signed download URL), and `GET /api/v1/download` (streams APK from R2). Tested with `worker/test/index.test.ts` (4 tests passing).
  - `scripts/publish-release.ps1`: ASCII-only PowerShell 5.1 script that discovers `appId`/`versionName`/`versionCode` from Flutter `pubspec.yaml` or Android `build.gradle.kts`, extracts the newest `CHANGELOG.md` notes, computes the APK SHA-256 hash, writes `dist/version.json`, uploads APK + `version.json` to Cloudflare R2 (via `wrangler` or `aws s3 cp`), and sends an `ntfy` notification.
- **Phase 2 — Shared Client SDKs:**
  - `packages/app_updater_flutter` (0.1.0): `AppReleaseManifest`, `UpdateService` (streaming SHA-256 verification, `http`, `package_info_plus`, `open_filex`), `UpdatePromptDialog` (Material 3, `< 400px` `Wrap` layout, verified 4.5:1 WCAG contrast in light & dark themes), and `CheckForUpdateTile` (in-app "Check for Update" widget). 8 tests + `flutter analyze` passing.
  - `packages/app-updater-android` (0.1.0): pure Kotlin `AppReleaseManifest` parser (zero `org.json` usage so `testDebugUnitTest` never hits Android stub errors), `UpdateClient` (single-pass streaming `MessageDigest` SHA-256 verification), `ApkInstaller` (`FileProvider` + `ACTION_VIEW` intent), Jetpack Compose `UpdatePromptDialog` + `CheckForUpdateRow`, and `AppUpdaterTest.kt`.
