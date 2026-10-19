# AppUpdater

Private in-app update gateway (**Cloudflare Worker + R2**), `app-updater/1` manifest contract, release publisher script (`scripts/publish-release.ps1`), and reusable client SDKs for **Flutter** (`packages/app_updater_flutter`) and **native Android / Kotlin** (`packages/app-updater-android`).

## Structure
- [`contracts/`](contracts/README.md) — `app-updater/1` JSON schema (`version-manifest.schema.json`) and API contract.
- [`docs/DESIGN.md`](docs/DESIGN.md) — Architecture, SDK specifications, and Switchboard integration.
- [`docs/ai-notes/PLAN.md`](docs/ai-notes/PLAN.md) — Project map (milestones, parts, decisions).
- `worker/` — Cloudflare Worker gateway (`GET /api/v1/version/:appId`, `GET /api/v1/update/:appId`, `GET /api/v1/download`).
- `scripts/` — `publish-release.ps1` (uploads APK + `version.json` to R2 and sends an `ntfy` notification).
- `packages/app_updater_flutter/` — Shared Flutter updater package (on-launch check, update modal dialog, and "Check for Update" settings tile).
- `packages/app-updater-android/` — Shared native Android/Kotlin updater module (`kotlinx.serialization`, `OkHttp` streaming SHA-256 verification, `FileProvider` installer, Jetpack Compose UI).
