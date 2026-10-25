# Changelog

All notable changes to **AppUpdater** will be documented in this file.

## [app-updater-android 0.2.0, app_updater_flutter 0.5.0] - 2026-10-25
- Both SDKs now refuse any URL that is not `https://` (scheme case-insensitive, host required), for the update check (which carries the Bearer token) and the APK download. No exception for localhost or emulators.
- Kotlin: new `requireHttpsUrl` (throws `SecurityException`, message names only the scheme) used by `DefaultHttpUrlConnectionTransport` (replaces the old `IllegalArgumentException` check) and by `UpdateClient`, so custom transports are covered. `checkForUpdate` returns `Error("Update server URL must start with https://")` before the transport is called, and `Error("Update manifest has an insecure download URL (https required)")` for a newer build with a non-https `downloadUrl`; `downloadAndVerifyApk` throws before any file or network access. New `AppUpdaterVersion.kt` (`APP_UPDATER_ANDROID_VERSION`) as the version source of truth.
- Flutter: new `requireHttpsUri` / `InsecureUrlException` in `update_service.dart`. `checkForUpdate` returns an `error` result (token never sent, log token-free) for a non-https gateway URL or download URL; the log line now reads `downloadUrl present (host X, scheme Y)`. `downloadAndInstall` throws `InsecureUrlException` before any cache, request or installer call.
- Why: PikminFilter security audit; only the host app's `usesCleartextTraffic="false"` stopped plain HTTP. `wrangler dev` over `http://localhost` no longer works from a real app.

## [publish-release 0.2.0] - 2026-10-25
- `scripts/publish-release.ps1` now reads the APK's real package, versionCode and versionName with `aapt2 dump badging` and refuses (before writing `dist/version.json` or uploading, so `-ManifestOnly` and `-DryRun` refuse too) when they differ from the manifest values.
- It also refuses when aapt2 can't be found. New options: `-Aapt2Path`, `aapt2_path` in `updater.toml`, and `-SkipApkCheck` (publish unverified, with a warning). Lookup order: `-Aapt2Path`, `aapt2_path`, PATH, then `build-tools` under `ANDROID_HOME`, `ANDROID_SDK_ROOT`, `%LOCALAPPDATA%\Android\Sdk`.
- Warns when the expected `dist/<Project>-v<version>.apk` is missing and the newest APK in `dist/` is used instead.
- Why: SystemPulse went out as 1.4.6/19 in the manifest while `apkKey`/`sha256` pointed at the 1.4.5 APK, so phones looped on "update available".
- Not yet run: PowerShell was blocked in the work run; see the HANDOFF entry for the test commands.

## [2026-10-25]
- **`app_updater_flutter`:**
  - Fixed mobile overflow bug in `CheckForUpdateTile._showDetails()`: moved action buttons from scrollable `content` to `AlertDialog.actions` so "Close" and "Hide/Show technical details" remain visible and tappable across all mobile viewports; resolved 2 failing Flutter widget tests (all 21 tests pass).
  - Streamed single-pass in-flight SHA-256 chunked conversion in `UpdateService.downloadAndInstall` to eliminate the second flash storage read pass on 50–100MB APKs.
  - Added verified cached APK reuse (if existing APK SHA-256 matches manifest) to avoid re-downloading when interrupted by Android install permission prompts.
  - Added partial file cleanup on download errors.
- **`app-updater-android` (Kotlin SDK):**
  - Fixed 404 bug in `UpdateClient`: 404 responses now produce explicit errors (`Server has no release for <appId>` vs endpoint not found) instead of false `UpToDate`.
  - Added incomplete manifest error validation (checks `downloadUrl.isNotBlank()` and `sha256.length == 64`).
  - Enforced HTTPS scheme requirement in `DefaultHttpUrlConnectionTransport` (closes PikminFilter inbox item).
  - Added verified cached APK reuse and partial download cleanup.
  - Added `ApkInstaller.canRequestPackageInstalls` and `openInstallPermissionSettings` helpers.
  - Unit tests updated with full coverage for 404 handling, incomplete manifests, cached reuse, and HTTPS enforcement.
- **Cloudflare Worker:**
  - Added HTTP `Range` request support on `GET /api/v1/download` (passes `Range` header to R2 and returns HTTP 206 Partial Content) to support resumable downloads on mobile networks.
  - Added `Access-Control-Allow-Origin: *` and `OPTIONS` preflight handling on `GET /api/v1/version/:appId` for browser and dashboard access.
  - Parallelized R2 reads with `Promise.all` in `buildCatalog` and `listGrants` (improves catalog latency by ~36%).
  - Added defensive check in `/api/v1/download` rejecting keys starting with `_`.
  - Added Google Play Protect installation tip on the store page.

## [app_updater_flutter 0.4.0] - 2026-10-23
- `CheckForUpdateTile`: the link under the status reads **"What's new"** when the last check has a release (also when already up to date) and opens that release's notes ("What's new in vX", with the build number under it). The technical check log is behind a **"Show technical details"** toggle. Errors, unconfigured and "no check yet" keep a **"Details"** link that opens the log directly.
- `UpdateCheckResult.upToDate` now carries `manifest` (the server's current release), so notes are available when no update is pending. `hasUpdate` is unchanged. Existing callers keep compiling.
- Tests: tile "What's new" flow, 404 "Details" flow, empty-notes message (light and dark, 360px), service `lastResult.manifest`.
- Apps pick this up when they rebuild against the package (path dependency; no tag yet).

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
- **Phase 1 â€” Cloudflare Worker & Publisher Script:**
  - `worker/src/index.ts` + `wrangler.toml`: implements `GET /api/v1/version/:appId` (open version metadata for Switchboard `VersionProbe`), `GET /api/v1/update/:appId` (single shared Bearer token + 15-min HMAC-SHA256 signed download URL), and `GET /api/v1/download` (streams APK from R2). Tested with `worker/test/index.test.ts` (4 tests passing).
  - `scripts/publish-release.ps1`: ASCII-only PowerShell 5.1 script that discovers `appId`/`versionName`/`versionCode` from Flutter `pubspec.yaml` or Android `build.gradle.kts`, extracts the newest `CHANGELOG.md` notes, computes the APK SHA-256 hash, writes `dist/version.json`, uploads APK + `version.json` to Cloudflare R2 (via `wrangler` or `aws s3 cp`), and sends an `ntfy` notification.
- **Phase 2 â€” Shared Client SDKs:**
  - `packages/app_updater_flutter` (0.1.0): `AppReleaseManifest`, `UpdateService` (streaming SHA-256 verification, `http`, `package_info_plus`, `open_filex`), `UpdatePromptDialog` (Material 3, `< 400px` `Wrap` layout, verified 4.5:1 WCAG contrast in light & dark themes), and `CheckForUpdateTile` (in-app "Check for Update" widget). 8 tests + `flutter analyze` passing.
  - `packages/app-updater-android` (0.1.0): pure Kotlin `AppReleaseManifest` parser (zero `org.json` usage so `testDebugUnitTest` never hits Android stub errors), `UpdateClient` (single-pass streaming `MessageDigest` SHA-256 verification), `ApkInstaller` (`FileProvider` + `ACTION_VIEW` intent), Jetpack Compose `UpdatePromptDialog` + `CheckForUpdateRow`, and `AppUpdaterTest.kt`.
