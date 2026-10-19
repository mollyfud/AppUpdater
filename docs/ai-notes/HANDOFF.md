# Handover log

Newest entries first. Rules: `AGENTS.md`, and the global rules (`~/.claude/CLAUDE.md` = `~/.gemini/AGENTS.md`).

### 2026-10-20 - Antigravity on DADSLAPTOP (Live Cloudflare deployment & successful OTA update test on Android)
- **Did:**
  - Deployed Cloudflare Worker `molly-app-updater` live to `https://molly-app-updater.mollysoft.workers.dev` bound to R2 bucket `private-app-releases`.
  - Configured Worker secrets: `APP_UPDATER_TOKEN` and `HMAC_SECRET`.
  - Updated default gateway URL across Switchboard App and PikminFilter to `https://molly-app-updater.mollysoft.workers.dev`.
  - Added persistent TopAppBar Settings (⚙) icon and modal dialog to PikminFilter with in-app token configuration and update check.
  - Bumped PikminFilter to dummy version `v0.6.1+12`, built release APK, and published to R2 using `publish-release.ps1`.
  - Tested OTA update live on Android phone: checked for update, verified changelog dialog, downloaded from R2, verified SHA-256 checksum in memory, and completed in-place APK installation.
- **Versions:** PikminFilter v0.6.0+11 -> v0.6.1+12 (verified OTA update).
- **Decisions:** Persistent TopAppBar Settings (⚙) icon established as standard pattern for companion apps.
- **Verified:** Live OTA upgrade on Molly's Android device (v0.6.0 -> v0.6.1).
- **Not verified / next:** Roll out `app_updater_flutter` across remaining Flutter apps (TennisSpark, NotebookMS, AFLStatsSystem, WordpressLiveBlogger, Site Pulse, SystemPulse).
- **Gotchas:** `publish-release.ps1` supports both `-ProjectPath` and `-ProjectDir`.

### 2026-10-20 - Antigravity on DADSLAPTOP (Phase 4: Pilot rollout across Switchboard Flutter and PikminFilter Android/Kotlin)
- **Did:**
  - **Switchboard Flutter App:**
    - Added `app_updater_flutter` path dependency in `packages/switchboard_app/pubspec.yaml` (relaxed `package_info_plus` constraint to `>=8.0.0 <11.0.0`).
    - Configured Android permissions (`REQUEST_INSTALL_PACKAGES`, `INTERNET`) and `FileProvider` (`file_paths.xml`) in `AndroidManifest.xml`.
    - Added `updaterUrl` and `updaterToken` fields to `HubSettings` in `lib/services/settings.dart` with default gateway URL `https://updater.mollyfud.com`.
    - Added `CheckForUpdateTile` and gateway/token settings fields to `lib/views/settings_view.dart`.
    - Integrated on-launch update check via `UpdatePromptDialog.checkOnLaunch` in `lib/main.dart`.
    - Added `test/updater_integration_test.dart`.
  - **PikminFilter (Android/Kotlin):**
    - Included `:app-updater-android` library module in `settings.gradle.kts` and added library plugin to `build.gradle.kts`.
    - Added `app-updater-android` dependency to `app/build.gradle.kts`.
    - Configured `INTERNET`, `REQUEST_INSTALL_PACKAGES` permissions and `FileProvider` (`file_paths.xml`) in `app/src/main/AndroidManifest.xml`.
    - Integrated `UpdateClient` and Compose `CheckForUpdateRow` into `MainActivity.kt`.
    - Updated `build-apk.ps1` to compute SHA-256 and generate `dist/version.json` on release builds matching `app-updater/1`.
  - Updated `PLAN.md` and `CHANGELOG.md`.
- **Versions:** no product bump to SDKs (pilot app integrations).
- **Decisions:** Followed Phase 4 plan.
- **Verified:**
  - Switchboard App: `flutter test test/updater_integration_test.dart` (2 passed), `flutter test test/settings_defaults_dropdown_test.dart test/settings_idle_default_test.dart test/settings_stale_model_test.dart` (22 passed), `flutter analyze` (0 issues).
  - PikminFilter: `.\gradlew.bat testDebugUnitTest` (44 tasks, all tests passed in `:app` and `:app-updater-android`), `.\build-apk.ps1 -SkipTests` (generated debug/release APK + `dist/version.json` with SHA-256 matching `app-updater/1`).
- **Not verified / next:** Deploy the Cloudflare Worker + R2 bucket live, set the shared token, and roll out to the remaining Flutter client apps (TennisSpark, NotebookMS, AFLStatsSystem, etc.).
- **Gotchas:** `InputDecoration` in Flutter requires non-`const` when referencing dynamic text styles; `FileProvider` authorities must match `<packageName>.fileprovider`.

### 2026-10-20 - Antigravity on DADSLAPTOP (Phase 1 & Phase 2: Cloudflare Worker, publish-release.ps1, Flutter SDK, and Android/Kotlin SDK)
- **Did:**
  - **Phase 1 (Cloudflare Worker & Publisher Script):**
    - Built `worker/src/index.ts`, `worker/wrangler.toml`, `worker/package.json`, `worker/tsconfig.json`, and `worker/test/index.test.ts`. Implements `GET /api/v1/version/:appId` (open read-only metadata for Switchboard's `VersionProbe`), `GET /api/v1/update/:appId` (constant-time Bearer token check + HMAC-SHA256 signed download URL), and `GET /api/v1/download` (streams APK from R2).
    - Built `scripts/publish-release.ps1` (ASCII-only for Windows PowerShell 5.1): discovers `appId`, `versionName`, and `versionCode` from `build.gradle.kts` / `pubspec.yaml`, extracts the latest `CHANGELOG.md` entry, computes SHA-256, writes `dist/version.json`, uploads APK + `version.json` to Cloudflare R2 (via `wrangler r2 object put` or `aws s3 cp`), and posts an instant update notification to `ntfy`.
  - **Phase 2 (Flutter & Android/Kotlin Client SDKs):**
    - Built `packages/app_updater_flutter` (`lib/app_updater_flutter.dart`, `src/manifest.dart`, `src/update_service.dart`, `src/update_dialog.dart`, `src/check_update_tile.dart`, `test/app_updater_flutter_test.dart`). Uses streaming SHA-256 (`sha256.bind(apkFile.openRead())`), UTF-8 body decoding, `< 400px` mobile-safe `Wrap` buttons, and explicit light/dark color palettes verified at >= 4.5:1 contrast.
    - Built `packages/app-updater-android` (`build.gradle.kts`, `AppReleaseManifest.kt`, `UpdateClient.kt`, `ApkInstaller.kt`, `ui/UpdatePromptDialog.kt`, `AppUpdaterTest.kt`). Uses a zero-dependency pure Kotlin JSON parser (no `org.json`) and single-pass `MessageDigest` SHA-256 verification.
  - Updated `CHANGELOG.md` and `docs/ai-notes/PLAN.md` (marked Phase 1 and Phase 2 done).
- **Versions:** contract `app-updater/1` 1.0.0, worker 0.1.0, `app_updater_flutter` 0.1.0, `app-updater-android` 0.1.0.
- **Decisions:** Following Molly's decisions D-0001 through D-0004 (Cloudflare Worker + R2, single shared Bearer token, check on app start + `ntfy` push on publish + in-app `CheckForUpdateTile`/`CheckForUpdateRow`, Android APKs first).
- **Verified:**
  - Worker unit tests: `node --test test/index.test.ts` in `worker/` -> 4 passed.
  - Publisher script smoke test: `powershell -File scripts\publish-release.ps1 -ManifestOnly` on a temp project -> generated valid `dist/version.json` with SHA-256 and changelog notes.
  - Flutter SDK: `flutter test` (8 passed, including WCAG 4.5:1 light/dark contrast checks, streaming SHA-256 verification, and 360px mobile widget tests) and `flutter analyze` (0 issues).
- **Not verified / next:**
  - Live deployment of Cloudflare Worker + R2 bucket (`private-app-releases`) and setting `APP_UPDATER_TOKEN` / `HMAC_SECRET` secrets via Wrangler.
  - Phase 3: Wire `publish-release.ps1` and the `publish_apk` action into `Switchboard`.
  - Phase 4: Pilot rollout in `Switchboard` (Flutter) and `PikminFilter` (Kotlin, where `gradlew testDebugUnitTest` will also run `AppUpdaterTest.kt`).
- **Gotchas:** `http.Response.body` in Dart defaults to `latin1` when no `charset` parameter is on the `Content-Type` header; `UpdateService.checkForUpdate` explicitly uses `utf8.decode(response.bodyBytes)` so bullet characters (`•`) in `releaseNotes` never fail to decode.

### 2026-10-20 - Antigravity on DADSLAPTOP (Initial project setup, contract app-updater/1, and design)
- **Did:**
  - Scaffolded `C:\antigravity\AppUpdater` and registered it in `C:\antigravity\AGENTS.md`.
  - Updated `AGENTS.md` with project conventions (Cloudflare Worker + R2, single token, on-launch check + `ntfy` push + manual "Check for Update" button, Flutter & Kotlin testing/UI rules).
  - Created `contracts/version-manifest.schema.json` and `contracts/README.md` (`app-updater/1` v1.0.0).
  - Created `docs/DESIGN.md` and `docs/ai-notes/PLAN.md` (with decisions D-0001 through D-0004 and milestones Phase 1–4).
  - Updated `.gitignore` to cover Cloudflare Wrangler, Node, Flutter, Android/Gradle, and signing keys/secrets.
- **Versions:** contract `app-updater/1` 1.0.0, project 0.1.0 initial.
- **Decisions:** Molly confirmed (2026-10-20):
  - D-0001: Use Cloudflare Worker + R2 (`private-app-releases`) to save Railway usage.
  - D-0002: Single shared Bearer token across private apps.
  - D-0003: Check on app launch + instant `ntfy` push on publish + manual in-app "Check for Update" option (no background `WorkManager` polling).
  - D-0004: Target Android APKs first (Flutter + Kotlin/Android); Windows desktop updates later if needed.
- **Verified:** Git repo initialized on `main`, `PLAN.md` follows `skills/project_map.md` format.
- **Not verified / next:** Implement Phase 1 (`worker/` Cloudflare Worker + tests, and `scripts/publish-release.ps1`) and Phase 2 (`packages/app_updater_flutter` and `packages/app-updater-android`).
- **Gotchas:** None.

### 2026-10-20 - Switchboard Scaffolding (project initialized)
- **Did:** Initial project scaffolding created with standard AI rules, memory, and skills.
- **Versions:** 0.1.0 initial
- **Decisions:** Created as blank project.
- **Verified:** Scaffolding complete and git repository initialized.
- **Not verified / next:** Initial project implementation.
- **Gotchas:** None.
