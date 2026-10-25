# Handover log

Newest entries first. Rules: `AGENTS.md`, and the global rules (`~/.claude/CLAUDE.md` = `~/.gemini/AGENTS.md`).

### 2026-10-25 - Claude Code (Publisher checks APK version with aapt2; Switchboard work run for job 01M5S3YNR5S4M48YKY8DS9WBKQ)
- **Did:** `scripts/publish-release.ps1` 0.1.0 -> 0.2.0: `Find-Aapt2`, `Get-ApkBadging`, step 3b compares package/versionCode/versionName from `aapt2 dump badging` with the manifest values and throws before version.json is written; fallback-APK warning; new `-Aapt2Path`, `-SkipApkCheck`, `aapt2_path` in updater.toml. CHANGELOG, README, contracts/README, AGENTS.md bullet, PLAN (part, Next, D-0011) updated. Messages to SystemPulse and Switchboard in the run output. Switchboard commits; no hash.
- **Versions:** publish-release 0.1.0 -> 0.2.0 (no contract change).
- **Decisions:** Molly (2026-10-25): refuse when aapt2 is missing unless `-SkipApkCheck` (D-0011).
- **Verified:** ASCII-only (Grep for non-ASCII bytes: none). Nothing else: PowerShell and Bash commands were denied in the run, so the script has NOT been executed or even parse-checked.
- **Not verified / next:** run the plan's cases by hand in `powershell` and `pwsh` with a temp project (pubspec.yaml, android\app\build.gradle.kts, dist\ with a real APK): matching values with `-DryRun -SkipNtfy` prints `[OK] APK matches`; pubspec versionCode +1 prints the fallback warning then throws and leaves dist\version.json untouched; different versionName and applicationId throw; `-Aapt2Path C:\nope\aapt2.exe` with ANDROID_HOME/ANDROID_SDK_ROOT/LOCALAPPDATA pointed at empty folders refuses, and adding `-SkipApkCheck` warns and continues. Then Molly publishes SystemPulse 1.4.7+20 via `publish_apk`; the live 1.4.6 manifest stays wrong until then.
- **Gotchas:** the check runs before `-ManifestOnly`/`-DryRun` returns, so those refuse too. The publishing PC needs Android build-tools.

### 2026-10-25 - Antigravity on DADSLAPTOP (Full project review & fixes: Flutter dialog layout & in-flight hash, Kotlin 404 & HTTPS parity, Worker Range & parallel R2)
- **Did:**
  - `packages/app_updater_flutter`:
    - Fixed dialog action button layout in `CheckForUpdateTile._showDetails()`: moved buttons into `AlertDialog.actions` so "Close" and toggle remain pinned on screen at all viewport heights (< 800px); resolved 2 failing tests in `app_updater_flutter_test.dart` (all 21 pass).
    - `UpdateService.downloadAndInstall`: converted SHA-256 calculation to single-pass in-flight chunked streaming via `_DigestSink`, eliminating the redundant second flash storage read pass on 50–100MB APKs.
    - Added verified cached APK reuse (if existing APK's SHA-256 matches manifest) to prevent re-downloads when interrupted by Android install permission prompts, and added partial file deletion on error in `catch`.
  - `packages/app-updater-android`:
    - `UpdateClient`: fixed 404 handling so 404 returns an explicit error (`Server has no release for <appId>` vs endpoint missing) rather than false `UpToDate`. Added incomplete manifest validation (`downloadUrl` and 64-char `sha256`).
    - Enforced HTTPS requirement in `DefaultHttpUrlConnectionTransport` (closes PikminFilter inbox item).
    - Added verified cached APK reuse and partial download cleanup.
    - Added `ApkInstaller.canRequestPackageInstalls` and `openInstallPermissionSettings` helpers.
    - Updated JUnit tests in `AppUpdaterTest.kt` with full coverage for 404 handling, incomplete manifests, cached reuse, and HTTPS enforcement.
  - `worker`:
    - Added HTTP `Range` request support to `GET /api/v1/download` (passes `Range` header to R2 and returns HTTP 206 Partial Content when range is fulfilled) to support interrupted/resumable downloads on mobile data.
    - Added `Access-Control-Allow-Origin: *` and `OPTIONS` preflight handling to `GET /api/v1/version/:appId` for browser and web dashboard integration.
    - Parallelized R2 reads with `Promise.all` in `buildCatalog` and `listGrants` (reduces catalog latency by ~36%).
    - Added defensive check in `/api/v1/download` rejecting keys with `_` prefix (e.g. `_grants/`).
    - Added Google Play Protect installation tip on the store page.
  - Docs: `INBOX.md` (PikminFilter item closed), `PLAN.md` (updated), `CHANGELOG.md` (updated).
- **Versions:** no product bump (internal hardening and parity fixes across worker, Flutter SDK, and Kotlin SDK).
- **Decisions:** Molly asked for a full review and implementation of fixes.
- **Verified:**
  - `npm test` in `worker/`: 33/33 tests passing (including CORS and OPTIONS checks).
  - `npx wrangler deploy --dry-run` in `worker/`: bundles cleanly (26.96 KiB).
  - `flutter test` in `packages/app_updater_flutter`: all 21 tests passing (including mobile width 360px hit-test tests).
  - `flutter analyze` in `packages/app_updater_flutter`: clean (no issues).
- **Not verified / next:**
  - Kotlin SDK Android unit tests on a device/emulator.
  - Worker deploy to live (`npx wrangler deploy`) and custom domain setup still pending Molly's deployment steps.
- **Gotchas:** None.

### 2026-10-23 - Claude Code (Release notes in tile Details; Switchboard work run, job 01M5GEGM008T2Z5G8W65RX5GET)
- **Did:** `app_updater_flutter`: `UpdateCheckResult.upToDate` takes/keeps `manifest` (manifest.dart, passed in update_service.dart); `CheckForUpdateTile` keeps `_lastResult`, link reads "What's new" (manifest) or "Details", dialog shows release notes first with a "Show/Hide technical details" toggle, errors open the log directly. Tests added/updated; CHANGELOG, PLAN (part, Next, D-0010, Kotlin note) updated. WordpressLiveBlogger inbox item done and removed from INBOX.md (TennisSpark item left). Message sent to WordpressLiveBlogger via the run output. Switchboard commits; no hash.
- **Versions:** app_updater_flutter 0.3.0 -> 0.4.0.
- **Decisions:** Molly (2026-10-23): link says "What's new" with notes, "Details" otherwise; up-to-date still shows current release notes titled "What's new in vX" (D-0010).
- **Verified:** see the run's test report below/in the summary (flutter commands from the package folder were blocked in the run if noted there).
- **Not verified / next:** look on a real phone after WordpressLiveBlogger rebuilds. Kotlin `CheckForUpdateRow` parity still parked (D-0006).
- **Gotchas:** none.

### 2026-10-22 - Claude Code (Pushed main to GitHub)
- **Did:** Molly said "push it": pushed `main` (`0ff0b16..c3b52ba`, the sharing work + custom domain) to origin. PLAN Next no longer says main is unpushed; this note committed and pushed too.
- **Versions:** no product change.
- **Decisions:** push only; no tag, no deploy.
- **Verified:** `git status` shows main even with origin/main after the push.
- **Not verified / next:** Worker 0.2.0 and update.aflspace.com are still NOT deployed (steps in the entries below). No release tag yet.
- **Gotchas:** none.

### 2026-10-22 - Claude Code (Custom domain update.aflspace.com in wrangler.toml; local commit)
- **Did:** `worker/wrangler.toml`: `routes = [{ pattern = "update.aflspace.com", custom_domain = true }]` and explicit `workers_dev = true`. Committed all of the 2026-10-21 sharing work plus this, locally (no push).
- **Versions:** no product change (deploy config only).
- **Decisions:** Molly: front the gateway with `update.aflspace.com` (aflspace.com is in her Cloudflare account), add it to wrangler.toml, commit locally. workers.dev kept on because installed apps have that address in their Settings. `updater.toml` `gateway_url` should become `https://update.aflspace.com` so invite links use it.
- **Verified:** `wrangler deploy --dry-run` accepts the config. The custom domain itself is NOT live until the next `npx wrangler deploy` (Molly); then check `https://update.aflspace.com/health`.
- **Not verified / next:** deploy steps from the entry below. `update.aflspace.com` must have no existing DNS record or the custom-domain attach fails. Switchboard's default gateway (`https://updater.mollyfud.com`, does not resolve) could switch to this domain - Molly to decide (Switchboard inbox not written).
- **Gotchas:** none.

### 2026-10-21 - Claude Code (App sharing built: Worker 0.2.0, contract app-updater/1 1.1.0)
- **Did:** Built steps A-C of `docs/design/sharing-and-store.md`.
  - Worker: `src/access.ts` (grant hashing/validity), `src/store-page.ts` (store HTML/JS, palette, CSP headers), `src/version.ts`; `src/index.ts` adds grant auth on `/update/:appId`, `GET /api/v1/catalog`, `GET /store` + `/store.js`, `GET /` -> `/store`, admin API `/api/v1/admin/{apps,grants,grants/:id/revoke,listing/:appId}`, `Content-Disposition` on downloads, `worker` in `/health`. `package.json` 0.1.0 -> 0.2.0, `wrangler.toml` comment for the new secret.
  - Scripts: `scripts/grant-access.ps1` (create / -List / -Revoke by name or id), `scripts/set-listing.ps1` (-Shareable/-Unshare, -Title, -Summary, -List), shared `scripts/updater-admin.ps1`. Config from env `APP_UPDATER_URL` / `APP_UPDATER_ADMIN_TOKEN` or `gateway_url` / `admin_token` in `%LOCALAPPDATA%\Switchboard\updater.toml`.
  - Contract: `contracts/README.md` 1.1.0 section 4, new `access-grant.schema.json`, `store-listing.schema.json`. Manifest schema, both SDKs and `publish-release.ps1` unchanged.
  - AGENTS.md (sharing rule + Worker export convention), CHANGELOG, PLAN (Phase 6, D-0007..D-0009 decided, I-0002 planned), design doc Decision section. Not committed.
- **Versions:** Worker 0.1.0 -> 0.2.0; contract app-updater/1 1.0.0 -> 1.1.0. SDKs unchanged.
- **Decisions:** Molly: "take the default for all decisions" -> D-0007 grants + store page, D-0008 R2 `_grants/`, D-0009 keep master token. My deviations from the proposal (in the design doc): listing in its own file (publishes rewrite version.json); grants via an admin API with a separate admin secret (Wrangler can't list R2; phone token mustn't mint grants); no icons yet.
- **Verified:** `npm test` in `worker/` -> 33 pass (incl. contrast 4.5:1 light/dark, export guard). `wrangler deploy --dry-run` bundles (25.7 KiB). End-to-end on `wrangler dev --local` (made-up test secrets via `--var`, seeded fake releases in local R2): both scripts in Windows PowerShell 5.1 and PowerShell 7 (create with warnings, set listing, list, revoke by name, unknown name error); store page in the browser pane at 375px light + dark (no horizontal scroll, token stripped from the address bar, only shared app shown, `["*"]` grant still hides unshared app, revoked token -> login with message, invite opened in an open tab reloads). Download checked by fetching the signed URL from the page (200, filename header), not by saving a file.
- **Not verified / next:** NOT deployed; no real grant exists. Real phone install from the store page (Android browser download + "install unknown apps") and pasting a grant token into an app's Settings are untested. Molly's steps: (1) `npx wrangler secret put APP_UPDATER_ADMIN_TOKEN` in `worker/` (new random value); (2) add `gateway_url` and `admin_token` to `%LOCALAPPDATA%\Switchboard\updater.toml` on each PC that manages grants; (3) `npx wrangler deploy` in `worker/`, check `/health` shows `"worker":"0.2.0"` and an app still updates with the owner token; (4) `set-listing.ps1 -AppId <id> -Shareable -Title ...`, then `grant-access.ps1 -Name ... -Apps <id>`.
- **Inbox:** TennisSpark "go public, then tag" item left in place (Molly's call).
- **Gotchas:** First local run found that workerd refuses a non-function named export from `src/index.ts` (unit tests didn't catch it) - fixed and guarded by a test. A grant for an app that isn't marked shareable silently shows nothing to that person (the create output warns). `com.example.afl_flutter_app` should be renamed before it is shared. Local test state lives only in the session scratchpad.

### 2026-10-21 - Claude Code (Design proposal: sharing apps + poor man's app store)
- **Did:** Molly asked how to share an app with someone who must present a token first, and whether to build a small app store. Wrote `docs/design/sharing-and-store.md` (findings, 4 options, recommended 3-step plan: per-person grants in the Worker, `grant-access.ps1`, catalog endpoint + token-gated store page). Added I-0002 and D-0007..D-0009 to `PLAN.md`. Not committed.
- **Versions:** no product change.
- **Decisions:** none yet - all open as D-0007..D-0009 with defaults.
- **Verified:** read `worker/src/index.ts`, the contract and the Flutter SDK token handling to confirm the SDKs need no change for per-person tokens. Nothing built or tested.
- **Not verified / next:** Molly's calls on D-0007..D-0009; then Worker 0.2.0 (grants), the script, contract 1.1.0 + store page.
- **Inbox:** left the TennisSpark "go public, then tag" item in place (push/visibility is Molly's call).
- **Gotchas:** none.

### 2026-10-21 - Claude Code (material_ui fix, app_updater_flutter 0.3.0)
- **Did:** Side session started from TennisSpark work. Replaced `flutter/material.dart` with `material_ui/material_ui.dart` in `lib/src/check_update_tile.dart`, `lib/src/update_dialog.dart` and the test; added `material_ui: ^1.6.0`. Wrapped both `showDialog` calls (tile `_runCheck`, `checkOnLaunch`) in try/catch; new `UpdateService.recordDialogFailure` writes `dialog error: ...` to the report, the tile shows an error status. Bumped `appUpdaterFlutterVersion` and pubspec to 0.3.0, CHANGELOG, PLAN. Commit: see git log (local only).
- **Versions:** `app_updater_flutter` 0.2.0 -> 0.3.0.
- **Decisions:** Molly asked: commit locally, no push, no tag. Kept `Theme`-based palette unchanged (the import fix makes `Theme.of` read the app's theme).
- **Verified:** `flutter analyze` clean; `flutter test` in the package (incl. new material_ui light/dark dialog tests and dialog-failure test).
- **Not verified / next:** Not run on a phone. Push and tag are pending (Molly). TennisSpark and the other Flutter apps on Flutter 3.47 (NotebookMS, AFLStatsSystem, WordpressLiveBlogger, Site Pulse, SystemPulse, Switchboard app) must rebuild against it. Apps still on Flutter < 3.47 can't resolve `material_ui` the same way; untested.
- **Inbox:** done - "from TennisSpark: update dialog never opens in material_ui apps" (this entry); the push/tag part is left to Molly.
- **Gotchas:** `material_ui` constraint raises the package's effective Flutter floor (the pubspec `flutter: >=3.24.0` is now optimistic).

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
    - **AFLStatsSystem:** integrated `app_updater_flutter`, `FileProvider` + permissions, `MainNavigator` launch check, top AppBar Settings (âš™) bottom sheet with token config dialog and `CheckForUpdateTile`, updated `build-dist.ps1` to compute SHA-256 and emit `dist/version.json`. Built, tested, uploaded to Google Drive and published to Cloudflare R2 (`com.example.afl_flutter_app` v1.5.17+29). Committed (`7b82435`).
    - **WordpressLiveBlogger:** integrated `app_updater_flutter`, `FileProvider` + permissions, `AppShell` launch check, `BlogSelectorScreen` AppBar Settings (âš™) dialog with token config and `CheckForUpdateTile`, updated `build-all.ps1` with SHA-256 and `dist/version.json`. Built, tested, uploaded to Google Drive and published to Cloudflare R2 (`com.hawkspod.liveblogger` v1.26.2+42). Committed (`751de1e`).
    - **MollysWordPressStatsFlutterApp (Site Pulse):** integrated `app_updater_flutter`, `FileProvider` + permissions, `HomeShell` launch check, AppBar Settings (âš™) dialog with token config and `CheckForUpdateTile`, updated `build-dist.ps1` with SHA-256 and `dist/version.json`. Built, tested, uploaded to Google Drive and published to Cloudflare R2 (`com.mollysstudio.sitepulse_app` v0.14.1+23). Committed (`1c6379d`).
    - **SystemPulse:** integrated `app_updater_flutter`, `FileProvider` + permissions, `DashboardScreen` launch check, AppBar Settings (âš™) dialog with token config and `CheckForUpdateTile`, updated `build-apk.ps1` with SHA-256 and `dist/version.json`. Built, tested, uploaded to Google Drive and published to Cloudflare R2 (`com.hawkspod.pulse.pulse_flutter_app` v1.4.3+16). Committed (`65a383d`).
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
- **Gotchas:** `http.Response.body` in Dart defaults to `latin1` when no `charset` parameter is on the `Content-Type` header; `UpdateService.checkForUpdate` explicitly uses `utf8.decode(response.bodyBytes)` so bullet characters (`â€¢`) in `releaseNotes` never fail to decode.

### 2026-10-20 - Antigravity on DADSLAPTOP (Initial project setup, contract app-updater/1, and design)
- **Did:**
  - Scaffolded `C:\antigravity\AppUpdater` and registered it in `C:\antigravity\AGENTS.md`.
  - Updated `AGENTS.md` with project conventions (Cloudflare Worker + R2, single token, on-launch check + `ntfy` push + manual "Check for Update" button, Flutter & Kotlin testing/UI rules).
  - Created `contracts/version-manifest.schema.json` and `contracts/README.md` (`app-updater/1` v1.0.0).
  - Created `docs/DESIGN.md` and `docs/ai-notes/PLAN.md` (with decisions D-0001 through D-0004 and milestones Phase 1â€“4).
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
