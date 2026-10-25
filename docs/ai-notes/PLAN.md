# Project map
Updated: 2026-10-25 by Antigravity (Flutter SDK action layout & in-flight hash fix; Kotlin SDK 404 parity & HTTPS; Worker Range, CORS & parallel R2)

<!-- How to keep this file: skills/project_map.md (format: Switchboard contracts/README.md section 16).
     Update it at each milestone and before your handover entry. -->

## Milestones
- [done 2026-10-20] Phase 1 - Contract and Cloudflare gateway
- [done 2026-10-20] Phase 2 - Flutter and Kotlin SDKs
- [done 2026-10-20] Phase 3 - Switchboard build and publish integration
- [done 2026-10-20] Phase 4 - Rollout across client apps
- [current] Phase 5 - Field diagnostics and hardening
- [next] Phase 6 - Sharing apps with other people

## Parts
- [done] Project scaffolding and design (Phase 1 - Contract and Cloudflare gateway) - repo initialized, docs/DESIGN.md and contracts/version-manifest.schema.json written
- [done] Contract app-updater/1 (Phase 1 - Contract and Cloudflare gateway) - 1.0.0, contracts/version-manifest.schema.json and contracts/README.md
- [done] Cloudflare Worker and R2 gateway (Phase 1 - Contract and Cloudflare gateway) - 0.1.0, worker deployed at https://molly-app-updater.mollysoft.workers.dev, private-app-releases R2 bucket live
- [done] Publisher script publish-release.ps1 (Phase 1 - Contract and Cloudflare gateway) - 0.1.0, SHA-256, version.json generation, R2 upload via Wrangler, ntfy notification
- [done] Flutter SDK app_updater_flutter (Phase 2 - Flutter and Kotlin SDKs) - 0.1.0, UpdateService streaming SHA-256, UpdatePromptDialog, CheckForUpdateTile, 8 tests + flutter analyze passing
- [done] Android Kotlin SDK app-updater-android (Phase 2 - Flutter and Kotlin SDKs) - 0.1.0, pure Kotlin JSON parser (no org.json), UpdateClient streaming SHA-256, ApkInstaller, Compose UpdatePromptDialog + CheckForUpdateRow, JUnit tests
- [done] Switchboard build template and publish_apk action (Phase 3 - Switchboard build and publish integration) - flutter-build-apk.ps1, spoke 0.37.0 publish_apk action with tests passing
- [done] Pilot rollout Switchboard and PikminFilter (Phase 4 - Rollout across client apps) - Switchboard Flutter app and PikminFilter native Kotlin app integrated; live end-to-end OTA update v0.6.0 -> v0.6.1 verified on Android phone!
- [done] Rollout remaining Flutter apps (Phase 4 - Rollout across client apps) - TennisSpark, NotebookMS, AFLStatsSystem, WordpressLiveBlogger, MollysWordPressStatsFlutterApp (Site Pulse), SystemPulse all integrated, tested, built, version.json emitted, and published to R2 bucket.
- [done] Diagnosable update check, Flutter SDK 0.2.0 (Phase 5 - Field diagnostics and hardening) - 404 and incomplete manifest are errors, result summary with local/server build + HTTP status, token-free lastCheckLog/lastCheckReport, tile Details dialog; 16 tests + analyze passing
- [done] material_ui compatibility, Flutter SDK 0.3.0 (Phase 5 - Field diagnostics and hardening) - imports material_ui so the dialog opens and the tile follows the theme on Flutter 3.47; showDialog errors surface in tile and report; committed locally, not pushed or tagged
- [done] Release notes in tile Details, Flutter SDK 0.4.0 (Phase 5 - Field diagnostics and hardening) - link reads "What's new" and opens notes (also when up to date), log behind "Show technical details"; upToDate carries manifest; not pushed or tagged
- [done] Access grants, admin API and store page, Worker 0.2.0 / contract 1.1.0 (Phase 6 - Sharing apps with other people) - 33 worker tests; scripts and page checked end-to-end on local wrangler dev; not deployed
- [done] Kotlin SDK parity: 404 and incomplete manifest as errors, HTTPS scheme enforcement, cached APK reuse (Phase 5 - Field diagnostics and hardening) - app-updater-android UpdateClient.kt, DefaultHttpUrlConnectionTransport, and JUnit tests passing
- [waiting] Deploy sharing and first real share (Phase 6 - Sharing apps with other people) - waiting on Molly: admin secret, updater.toml keys, wrangler deploy, real phone install

## Next
- Rebuild WordpressLiveBlogger and the other Flutter apps against app_updater_flutter 0.4.0 (no tag yet), then check Settings > App updates > Check for Update > What's new on a phone
- Molly: deploy sharing (Worker 0.2.0) and the update.aflspace.com custom domain: set the new APP_UPDATER_ADMIN_TOKEN secret, add gateway_url (https://update.aflspace.com) + admin_token to updater.toml, deploy, check /health on the new domain, then a first real grant + listing (steps in HANDOFF 2026-10-21)
- Molly: tag AppUpdater (main is pushed; no release tag yet), then rebuild TennisSpark, NotebookMS, AFLStatsSystem, WordpressLiveBlogger, Site Pulse, SystemPulse and the Switchboard app on Flutter 3.47 against it
- Molly: send the hub message to TennisSpark and run a TennisSpark job (Details view, gateway URL https://molly-app-updater.mollysoft.workers.dev, app id com.hawkspod.tennisspark_app, bump past build 11), build it, sideload once from Google Drive, then read Settings > App updates > Details
- Then publish that build plus one more and confirm the phone self-updates without Google Drive
- Then Kotlin SDK parity for app-updater-android

## Needs your call

## Decided
- [D-0001] 2026-10-20 Molly: host the update gateway and APK storage on Cloudflare Worker + Cloudflare R2 (keeps bandwidth and storage off Railway)
- [D-0002] 2026-10-20 Molly: use a single shared Bearer token across private client apps
- [D-0003] 2026-10-20 Molly: check for updates on app start, send an instant ntfy push on release publish, and provide an in-app "Check for Update" button (no periodic background WorkManager polling)
- [D-0004] 2026-10-20 Molly: target Android APKs first (Flutter + Kotlin/Android); Windows desktop remote updates can come later if needed
- [D-0005] 2026-10-20 Molly: include debug logging and a stored last-check log in the diagnosable update check (closes the TennisSpark inbox item fully)
- [D-0006] 2026-10-20 Molly: Flutter SDK only for now; Kotlin SDK parity is parked in this map
- [D-0007] 2026-10-21 Molly: build app sharing as per-person grants + a token-gated web store page (default)
- [D-0008] 2026-10-21 Molly: keep access grants in R2 under _grants/ (default)
- [D-0009] 2026-10-21 Molly: keep the master token on her own devices for now (default)
- [D-0010] 2026-10-23 Molly: the tile link says "What's new" when the last result has release notes and "Details" for errors, unconfigured or no check yet; when up to date the dialog still shows the current release's notes, titled "What's new in vX"

## Ideas
- [I-0001] 2026-10-20, Molly (later): Windows desktop .zip self-updater using the artifacts map in version.json - docs/DESIGN.md
- [I-0002] 2026-10-21, Molly (planned): share apps with other people via per-person access tokens, plus a small token-gated web app store page on the Worker - docs/design/sharing-and-store.md
