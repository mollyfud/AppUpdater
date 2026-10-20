# Cross-project Inbox for AppUpdater

Work that agents in *other* projects (or on another machine) left for this project.
Rules: Section 4 of Molly's global working agreement (`~/.claude/CLAUDE.md` = `~/.gemini/AGENTS.md`).

### 2026-10-20 - from TennisSpark / Claude Code on DADSLAPTOP: update check says "up to date" with no way to see why
- **Ask:** in `app_updater_flutter` (`update_service.dart`, `check_update_tile.dart`), add debug logging to the update check and make the result diagnosable. Log (debugPrint, never the token) the endpoint called, app id, HTTP status, local vs server build, and the reason for the outcome, and keep the last check's log so an app can show it (TennisSpark wants it in Settings > App updates): a 404 currently returns `upToDate` (hides a wrong gateway URL or app id), and the "up to date" text shows only the local version. Show the remote build and HTTP status (e.g. "Up to date (local 9, server 11)", "Server has no release for <appId> (HTTP 404)"), and treat a missing/short `sha256` or empty `downloadUrl` on a newer build as an error, not up to date.
- **Why:** TennisSpark 0.7.0 (9) on Molly's phone says "You are up to date" although the gateway serves 0.9.0 (11): `GET /api/v1/update/com.hawkspod.tennisspark_app` with the token returns 200 with a valid manifest (checked from the PC). The phone shows no error, so the cause can't be told apart from the UI.
- **Urgency:** soon

