# Handover log

Newest entries first. Rules: `AGENTS.md`, and the global rules (`~/.claude/CLAUDE.md` = `~/.gemini/AGENTS.md`).

### 2026-10-20 - Claude Code (Follow-up run: get the new update check onto the phone)
- **Did:** Switchboard work run for job 01M5B9Q600NZ8K6JGQ80A62JF3 (Switchboard commits it; no hash here). The approved plan says no more AppUpdater code changes; all five steps happen in TennisSpark, in Switchboard, or on Molly's phone, which this run can't reach. Only change here: `docs/ai-notes/PLAN.md` `Updated:` line and Next rewritten to name the TennisSpark job and the sideload/self-update check.
- **Versions:** no product change (`app_updater_flutter` stays 0.2.0).
- **Decisions:** none new. No new messages, as the plan says: the TennisSpark and Switchboard messages from the previous run are still waiting on the hub for Molly to send.
- **Verified:** `flutter test` in `packages/app_updater_flutter` -> 16 passed (0.2.0 is the state TennisSpark will pick up via its path dependency).
- **Not verified / next:** Plan milestones 1-5 aren't done (send the TennisSpark message and run its job, build, sideload, read Details, check self-update). They need Molly and the TennisSpark project.
- **Gotchas:** none.

### 2026-10-20 - Claude Code on DADSLAPTOP (Diagnosable update check, app_updater_flutter 0.2.0)
- **Did:** Switchboard work run for job 01M5B9Q600NZ8K6JGQ80A62JF3 (Switchboard commits it; no hash here).
  - `lib/src/manifest.dart`: `UpdateCheckResult` gains optional `appId`, `endpoint`, `httpStatus`, `remoteVersionCode`, `remoteVersionName`, `missingSettings` and a `summary` getter. All factory params are optional named, so consumer code compiles unchanged.
  - `lib/src/update_service.dart`: 404 is now an error (JSON `App manifest not found` -> "Server has no release for <appId> (HTTP 404)", anything else -> "Update endpoint not found at <endpoint> (HTTP 404) - check the gateway URL"); newer build with sha256 length != 64 or empty downloadUrl -> error "manifest is incomplete"; 401/403/other errors include the endpoint. Token-free per-check log (`_log` -> `debugPrint('[app_updater] ...')`), new `lastCheckLog`, `lastCheckReport`, `lastResult`, and `appUpdaterFlutterVersion` const.
  - `lib/src/check_update_tile.dart`: status text = `result.summary`; new `showDetails` (default true) with a "Details" button (`check-for-update-details`) opening an `AlertDialog` with `SelectableText(lastCheckReport)`.
  - Tests: 8 new (404 x2, incomplete manifest x2, unconfigured, log/redaction/reset, 404 tile light+dark), up-to-date widget test now checks the summary text and the Details dialog, contrast test covers the tile pairs on `notesBoxBackground`.
  - `CHANGELOG.md`, `pubspec.yaml` 0.1.0 -> 0.2.0, `PLAN.md` (new milestone Phase 5, two parts, D-0005/D-0006, Next), inbox item removed.
- **Versions:** `app_updater_flutter` 0.1.0 -> 0.2.0. Worker, contract, Kotlin SDK unchanged.
- **Decisions:** Molly (2026-10-20): D-0005 include debug logging + stored last-check log; D-0006 Flutter only, Kotlin parity parked in PLAN.md. Added milestone "Phase 5 - Field diagnostics and hardening" so the new parts have a `[current]` milestone. Added `missingSettings` to the result (not in the plan's field list) so the unconfigured summary can name what is missing, as the plan asked.
- **Verified:** `flutter test` in `packages/app_updater_flutter` -> 16 passed; `flutter analyze` -> no issues.
- **Not verified / next:**
  - Consumer smoke check (`flutter analyze` + `flutter test test/updater_integration_test.dart` in `Switchboard/packages/switchboard_app`) was NOT run: the run sandbox denied access outside this repo. Any consumer test asserting the old "You are up to date (...)" text or a 404 being up to date will now fail; the API itself is additive. Sent to Switchboard via the run's messages.
  - Real diagnosis on the phone (rebuild TennisSpark, read Settings > App updates / Details). Sent to TennisSpark via the run's messages.
  - Kotlin parity (PLAN part, not started).
- **Inbox:** done - "from TennisSpark: update check says 'up to date' with no way to see why" (this entry).
- **Gotchas:** `UpdatePromptDialog.checkOnLaunch` stays silent on errors, so the new 404/incomplete errors only surface via the tile or `lastCheckReport`, not on launch. The tile's updateAvailable text is unchanged ("Update vX (build N) is available!"). The log keeps the raw `buildNumber` string so a non-numeric build number (parsed as 0) is visible. Lead from planning: Switchboard's default gateway is `https://updater.mollyfud.com` while the live Worker is `https://molly-app-updater.mollysoft.workers.dev`; if an app copied that default, the new log will show "Update endpoint not found" or a connect error.

### 2026-10-20 - Antigravity on DADSLAPTOP (Full client app rollout completed across all Flutter apps)
- **Did:**
  - Completed `app_updater_flutter` integration across all remaining client applications:
    - **TennisSpark:** integrated `app_updater_flutter`, `FileProvider` + `REQUEST_INSTALL_PACKAGES`, `AdaptiveShell` launch check, `SettingsScreen` updater card + token config dialog, updated `build-apk.ps1` with SHA-256 and `dist/version.json`. Built, tested, uploaded to Google Drive and published to Cloudflare R2 (`com.hawkspod.tennisspark_app` v0.7.0+9). Committed (`09c3f0c`).
    - **NotebookMS:** integrated `app_updater_flutter`, `FileProvider` + permissions, `HomeScreen` launch check, `SettingsScreen` updater tile + token config dialog, updated `build-apk.ps1`. Built, tested, uploaded to Google Drive and published to Cloudflare R2 (`com.hawkspod.notebookms_app` v0.8.0+9). Committed (`1bbbbf0`).
    - **AFLStatsSystem:** integrated `app_updater_flutter`, `FileProvider` + permissions, `MainNavigator` launch check, top AppBar Settings (⚙) bottom sheet with token config dialog and `CheckForUpdateTile`, updated `build-dist.ps1` to compute SHA-256 and emit `dist/version.json`. Built, tested, uploaded to Google Drive and published to Cloudflare R2 (`com.example.afl_flutter_app` v1.5.17+29). Committed (`7b82435`).
    - **WordpressLiveBlogger:** integrated `app_updater_flutter`, `FileProvider` + permissions, `AppShell` launch check, `BlogSelectorScreen` AppBar Settings (⚙) dialog with token config and `CheckForUpdateTile`, updated `build-all.ps1` with SHA-256 and `dist/version.json`. Built, tested, uploaded to Google Drive and published to Cloudflare R2 (`com.hawkspod.liveblogger` v1.26.2+42). Committed (`751de1e`).
    - **MollysWordPressStatsFlutterApp (Site Pulse):** integrated `app_updater_flutter`, `FileProvider` + permissions, `HomeShell` launch check, AppBar Settings (⚙) dialog with token config and `CheckForUpdateTile`, updated `build-dist.ps1` with SHA-256 and `dist/version.json`. Built, tested, uploaded to Google Drive and published to Cloudflare R2 (`com.mollysstudio.sitepulse_app` v0.14.1+23). Committed (`1c6379d`).
    - **SystemPulse:** integrated `app_updater_flutter`, `FileProvider` + permissions, `DashboardScreen` launch check, AppBar Settings (⚙) dialog with token config and `CheckForUpdateTile`, updated `build-apk.ps1` with SHA-256 and `dist/version.json`. Built, tested, uploaded to Google Drive and published to Cloudflare R2 (`com.hawkspod.pulse.pulse_flutter_app` v1.4.3+16). Committed (`65a383d`).
  - Added `.wrangler/` to `.gitignore` files to prevent caching artifacts in git.
  - Updated `PLAN.md` to reflect Phase 4 completion.
- **Versions:**
  - TennisSpark: v0.7.0+9
  - NotebookMS: v0.8.0+9
  - AFLStatsSystem: v1.5.17+29
  - WordpressLiveBlogger: v1.26.2+42
  - Site Pulse: v0.14.1+23
  - SystemPulse: v1.4.3+16
- **Decisions:** Dual-delivery preserved everywhere (build scripts copy to Google Drive for device bootstrap and emit `dist/version.json` for Cloudflare R2 updates).
- **Verified:** All test suites passed (`flutter test` across all 6 apps), all analyzers clean (`flutter analyze` with 0 issues), all release APKs compiled, SHA-256 hashes verified, manifests emitted, and both APKs and `version.json` successfully published to remote Cloudflare R2 bucket `private-app-releases` via Wrangler.
- **Not verified / next:** Real-device checks as apps are opened on Android.
- **Gotchas:** `UpdateService` requires non-null `authToken` (fall back to empty string `''` when unconfigured).

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
