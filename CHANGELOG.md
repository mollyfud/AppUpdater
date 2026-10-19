# Changelog

All notable changes to **AppUpdater** will be documented in this file.

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
