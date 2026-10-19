# Project map
Updated: 2026-10-20 by Antigravity on DADSLAPTOP (Phase 1 and Phase 2 built and verified)

<!-- How to keep this file: skills/project_map.md (format: Switchboard contracts/README.md section 16).
     Update it at each milestone and before your handover entry. -->

## Milestones
- [done 2026-10-20] Phase 1 - Contract and Cloudflare gateway
- [done 2026-10-20] Phase 2 - Flutter and Kotlin SDKs
- [done 2026-10-20] Phase 3 - Switchboard build and publish integration
- [current] Phase 4 - Rollout across client apps

## Parts
- [done] Project scaffolding and design (Phase 1 - Contract and Cloudflare gateway) - repo initialized, docs/DESIGN.md and contracts/version-manifest.schema.json written
- [done] Contract app-updater/1 (Phase 1 - Contract and Cloudflare gateway) - 1.0.0, contracts/version-manifest.schema.json and contracts/README.md
- [done] Cloudflare Worker and R2 gateway (Phase 1 - Contract and Cloudflare gateway) - 0.1.0, worker/src/index.ts, /api/v1/version, /api/v1/update, signed /api/v1/download, 4 unit tests passing
- [done] Publisher script publish-release.ps1 (Phase 1 - Contract and Cloudflare gateway) - 0.1.0, SHA-256, version.json generation, R2 upload via Wrangler or AWS CLI, ntfy notification
- [done] Flutter SDK app_updater_flutter (Phase 2 - Flutter and Kotlin SDKs) - 0.1.0, UpdateService streaming SHA-256, UpdatePromptDialog, CheckForUpdateTile, 8 tests + flutter analyze passing
- [done] Android Kotlin SDK app-updater-android (Phase 2 - Flutter and Kotlin SDKs) - 0.1.0, pure Kotlin JSON parser (no org.json), UpdateClient streaming SHA-256, ApkInstaller, Compose UpdatePromptDialog + CheckForUpdateRow, JUnit tests
- [done] Switchboard build template and publish_apk action (Phase 3 - Switchboard build and publish integration) - flutter-build-apk.ps1, spoke 0.37.0 publish_apk action with tests passing
- [done] Pilot rollout Switchboard and PikminFilter (Phase 4 - Rollout across client apps) - Switchboard Flutter app and PikminFilter native Kotlin app integrated and verified
- [not-started] Rollout remaining Flutter apps (Phase 4 - Rollout across client apps) - TennisSpark, NotebookMS, AFLStatsSystem, WordpressLiveBlogger, MollysWordPressStatsFlutterApp, SystemPulse

## Next
- Deploy the Cloudflare Worker (`npx wrangler r2 bucket create private-app-releases` and `npx wrangler deploy` in `C:\antigravity\AppUpdater\worker`)
- Roll out `app_updater_flutter` to remaining apps: TennisSpark, NotebookMS, AFLStatsSystem, etc.

## Needs your call

## Decided
- [D-0001] 2026-10-20 Molly: host the update gateway and APK storage on Cloudflare Worker + Cloudflare R2 (keeps bandwidth and storage off Railway)
- [D-0002] 2026-10-20 Molly: use a single shared Bearer token across private client apps
- [D-0003] 2026-10-20 Molly: check for updates on app start, send an instant ntfy push on release publish, and provide an in-app "Check for Update" button (no periodic background WorkManager polling)
- [D-0004] 2026-10-20 Molly: target Android APKs first (Flutter + Kotlin/Android); Windows desktop remote updates can come later if needed

## Ideas
- [I-0001] 2026-10-20, Molly (later): Windows desktop .zip self-updater using the artifacts map in version.json - docs/DESIGN.md
