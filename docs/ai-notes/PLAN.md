# Project map
Updated: 2026-10-20 by Antigravity on DADSLAPTOP (initial project setup and architecture plan)

<!-- How to keep this file: skills/project_map.md (format: Switchboard contracts/README.md section 16).
     Update it at each milestone and before your handover entry. -->

## Milestones
- [current] Phase 1 - Contract and Cloudflare gateway
- [next] Phase 2 - Flutter and Kotlin SDKs
- [later] Phase 3 - Switchboard build and publish integration
- [later] Phase 4 - Rollout across client apps

## Parts
- [done] Project scaffolding and design (Phase 1 - Contract and Cloudflare gateway) - repo initialized, docs/DESIGN.md and contracts/version-manifest.schema.json written
- [in-progress 20%] Contract app-updater/1 (Phase 1 - Contract and Cloudflare gateway) - JSON schema and README drafted
- [not-started] Cloudflare Worker and R2 gateway (Phase 1 - Contract and Cloudflare gateway) - worker/src/index.ts, /api/v1/version, /api/v1/update, signed /api/v1/download, unit tests
- [not-started] Publisher script publish-release.ps1 (Phase 1 - Contract and Cloudflare gateway) - SHA-256, version.json generation, R2 upload, ntfy notification
- [not-started] Flutter SDK app_updater_flutter (Phase 2 - Flutter and Kotlin SDKs) - UpdateService, UpdatePromptDialog, CheckForUpdateTile, widget and unit tests
- [not-started] Android Kotlin SDK app-updater-android (Phase 2 - Flutter and Kotlin SDKs) - kotlinx.serialization, OkHttp streaming SHA-256, FileProvider installer, Compose dialog, JVM unit tests
- [not-started] Switchboard build template and publish_apk action (Phase 3 - Switchboard build and publish integration) - flutter-build-apk.ps1, gradle-build-apk.ps1, spoke publish_apk action, VersionProbe config
- [not-started] Pilot rollout Switchboard and PikminFilter (Phase 4 - Rollout across client apps) - first Flutter app and first Kotlin app live-tested
- [not-started] Rollout remaining Flutter apps (Phase 4 - Rollout across client apps) - TennisSpark, NotebookMS, AFLStatsSystem, WordpressLiveBlogger, MollysWordPressStatsFlutterApp, SystemPulse

## Next
- Build `worker/` (Cloudflare Worker + Vitest/Miniflare tests) and `scripts/publish-release.ps1`
- Build `packages/app_updater_flutter` and `packages/app-updater-android` with unit and widget tests

## Needs your call

## Decided
- [D-0001] 2026-10-20 Molly: host the update gateway and APK storage on Cloudflare Worker + Cloudflare R2 (keeps bandwidth and storage off Railway)
- [D-0002] 2026-10-20 Molly: use a single shared Bearer token across private client apps
- [D-0003] 2026-10-20 Molly: check for updates on app start, send an instant ntfy push on release publish, and provide an in-app "Check for Update" button (no periodic background WorkManager polling)
- [D-0004] 2026-10-20 Molly: target Android APKs first (Flutter + Kotlin/Android); Windows desktop remote updates can come later if needed

## Ideas
- [I-0001] 2026-10-20, Molly (later): Windows desktop .zip self-updater using the artifacts map in version.json - docs/DESIGN.md
