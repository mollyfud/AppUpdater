# Project map
Updated: 2026-10-20 by Claude Code on DADSLAPTOP (job 01M5B9Q600NZ8K6JGQ80A62JF3, diagnosable Flutter update check)

<!-- How to keep this file: skills/project_map.md (format: Switchboard contracts/README.md section 16).
     Update it at each milestone and before your handover entry. -->

## Milestones
- [done 2026-10-20] Phase 1 - Contract and Cloudflare gateway
- [done 2026-10-20] Phase 2 - Flutter and Kotlin SDKs
- [done 2026-10-20] Phase 3 - Switchboard build and publish integration
- [done 2026-10-20] Phase 4 - Rollout across client apps
- [current] Phase 5 - Field diagnostics and hardening

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
- [not-started] Kotlin SDK parity: 404 and incomplete manifest as errors, diagnostics + log (Phase 5 - Field diagnostics and hardening) - app-updater-android UpdateClient.kt:94 and :114-125, parked by D-0006

## Next
- Rebuild TennisSpark with app_updater_flutter 0.2.0 and read Settings > App updates (status + Details) on Molly's phone to find why build 9 doesn't see build 11
- Then Kotlin SDK parity for app-updater-android

## Needs your call

## Decided
- [D-0001] 2026-10-20 Molly: host the update gateway and APK storage on Cloudflare Worker + Cloudflare R2 (keeps bandwidth and storage off Railway)
- [D-0002] 2026-10-20 Molly: use a single shared Bearer token across private client apps
- [D-0003] 2026-10-20 Molly: check for updates on app start, send an instant ntfy push on release publish, and provide an in-app "Check for Update" button (no periodic background WorkManager polling)
- [D-0004] 2026-10-20 Molly: target Android APKs first (Flutter + Kotlin/Android); Windows desktop remote updates can come later if needed
- [D-0005] 2026-10-20 Molly: include debug logging and a stored last-check log in the diagnosable update check (closes the TennisSpark inbox item fully)
- [D-0006] 2026-10-20 Molly: Flutter SDK only for now; Kotlin SDK parity is parked in this map

## Ideas
- [I-0001] 2026-10-20, Molly (later): Windows desktop .zip self-updater using the artifacts map in version.json - docs/DESIGN.md
