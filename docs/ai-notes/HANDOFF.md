# Handover log

Newest entries first. Rules: `AGENTS.md`, and the global rules (`~/.claude/CLAUDE.md` = `~/.gemini/AGENTS.md`).

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
