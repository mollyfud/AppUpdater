# AppUpdater - notes for AI agents

> Canonical agent notes. `CLAUDE.md` imports this file and `GEMINI.md` points here; edit here only.
> Also read `C:\antigravity\AGENTS.md` (workspace map) and the global rules.

Private in-app update gateway (**Cloudflare Worker + R2**), `app-updater/1` manifest contract, release publisher script (`scripts/publish-release.ps1`), and reusable client SDKs for **Flutter** (`packages/app_updater_flutter`) and **native Android / Kotlin** (`packages/app-updater-android`).

## Architecture & Decisions (Molly, 2026-10-20)
- **Backend Hosting (D-0001):** Cloudflare Worker + private Cloudflare R2 bucket (`private-app-releases`) to avoid adding bandwidth/storage load to Railway.
- **Authentication (D-0002):** Single shared Bearer token across Molly's private client apps (stored only in Cloudflare Worker secrets, `%LOCALAPPDATA%\Switchboard\updater.toml`, and per-device app settings — never in tracked files).
- **Sharing with other people (D-0007..D-0009, 2026-10-21, `docs/design/sharing-and-store.md`):** the shared token above stays as the *owner* token on Molly's devices. Other people get their own `aug_...` grant token (hash only stored at `_grants/` in R2), limited to apps whose `<appId>/listing.json` says `shareable`. Grants and listings are managed only through the admin API (`APP_UPDATER_ADMIN_TOKEN`, a separate Worker secret that never goes into an app) via `scripts/grant-access.ps1` and `scripts/set-listing.ps1`. The store page is `GET /store`. Never print or log grant tokens anywhere but the one-time script output.
- **Update Checks & Notifications (D-0003):**
  1. **On app start:** Foreground check against `GET /api/v1/update/:appId`, showing `UpdatePromptDialog` when `remote.versionCode > local.versionCode`.
  2. **Instant push via `ntfy`:** `scripts/publish-release.ps1` posts a notification to Molly's `ntfy` topic as soon as a new APK is uploaded to R2 (no battery-draining 12h background `WorkManager` polling needed across 8 apps).
  3. **Manual in-app check:** Both SDKs expose a "Check for Updates" tile/button for Settings/About screens with explicit feedback ("Up to date (vX.Y.Z)" or opens the update dialog).
- **Platform Scope (D-0004):** Android APKs first (Flutter Android + native Kotlin/Android such as `PikminFilter`). Windows desktop apps remain updated via Switchboard's local `build_windows` action for now; the `app-updater/1` manifest includes an optional `artifacts` map so Windows `.zip` bundles can be added later without breaking the contract.
- **Switchboard Integration:**
  - `GET /api/v1/version/:appId` is an open read-only endpoint returning only `{"appId", "version", "versionName", "versionCode", "releaseDate"}` (no download link) so Switchboard's `VersionProbe` (`[versions.<project>]` in `actions.toml`) can display the live published APK version alongside the repo's `code_version` on the Projects page.
  - Publishing is triggered via Switchboard's signed `publish_apk` project action (`high` risk, warned), never from inside an AI work run.

## Rules for this project
- Standing rules belong here; session history belongs in `docs/ai-notes/HANDOFF.md`; project map lives in `docs/ai-notes/PLAN.md`.
- Read `AGENTS.md`, `docs/ai-notes/HANDOFF.md`, `docs/ai-notes/PLAN.md`, and `docs/ai-notes/INBOX.md` before starting, and update `PLAN.md` + `HANDOFF.md` when you finish.
- **Contract first:** `contracts/version-manifest.schema.json` (`app-updater/1`) is the single source of truth for `version.json`. Keep the Worker, `publish-release.ps1`, `app_updater_flutter`, and `app-updater-android` in sync with it.
- **Version every component** (SemVer) and add a `CHANGELOG.md` entry per bump.
- **Never write secrets** (Cloudflare R2 keys, Worker tokens, HMAC secrets, signing keystores, `ntfy` topics) into tracked files or handover notes.

### Project conventions
- **Worker (`worker/`):** `src/index.ts` may export only the default handler and functions; workerd refuses to start on any other named export (a test guards this). Put constants in other modules. Run `npm test` and `npx wrangler deploy --dry-run` before a deploy.
- **PowerShell scripts (`scripts/*.ps1`):** Must be ASCII-only unless saved with a UTF-8 BOM so Windows PowerShell 5.1 parses them cleanly.
  - `publish-release.ps1` must check the APK's package, versionCode and versionName (`aapt2 dump badging`) against the manifest before writing version.json or uploading. It refuses when aapt2 is missing unless `-SkipApkCheck` is passed explicitly.
- **Flutter SDK (`packages/app_updater_flutter`):**
  - Only `https://` URLs may be fetched; route every URL through `requireHttpsUri`. No cleartext fallback, not even localhost (Molly, 2026-10-24).
  - Stream APK files when computing SHA-256 (`file.openRead().transform(sha256)`) rather than `readAsBytes()` to avoid OOM on large APKs.
  - Choose UI colours per theme brightness, pair every background with an explicit text colour, and check 4.5:1 contrast with a test in both light and dark themes.
  - Stack buttons or use `Wrap` inside dialogs on mobile widths (`< 400px`) to prevent `RenderFlex` overflows.
  - Avoid unmocked `CircularProgressIndicator` widgets in resting states so `tester.pumpAndSettle()` completes cleanly.
- **Android / Kotlin SDK (`packages/app-updater-android`):**
  - Only `https://` URLs may be fetched; route every URL through `requireHttpsUrl`. No cleartext fallback, not even localhost (Molly, 2026-10-24). SDK version lives in `AppUpdaterVersion.kt`.
  - Never use `org.json` in code tested by local JVM unit tests (`testDebugUnitTest`); use `kotlinx.serialization` to avoid `RuntimeException: Stub!`.
  - Stream downloads and pipe bytes through `MessageDigest.getInstance("SHA-256")` in a single pass.

## Handover
Log: `docs/ai-notes/HANDOFF.md` (newest first, signed with agent name and machine).
