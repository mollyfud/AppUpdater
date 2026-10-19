# AppUpdater - notes for AI agents

> Canonical agent notes. `CLAUDE.md` imports this file and `GEMINI.md` points here; edit here only.
> Also read `C:\antigravity\AGENTS.md` (workspace map) and the global rules.

Private in-app update gateway (Cloudflare Worker + R2), app-updater/1 contract, publisher script, and client SDKs (Flutter + Android/Kotlin)

## Rules for this project
- Standing rules belong here; session history belongs in `docs/ai-notes/HANDOFF.md`.
- Read `AGENTS.md` and `docs/ai-notes/HANDOFF.md` before starting, and add an entry when you finish.
- Read `docs/ai-notes/INBOX.md` for work from other projects.
- Version every shipped product (SemVer) with one source of truth, and keep a changelog entry per bump in `CHANGELOG.md`.
- Never write secrets into tracked files or handover notes.

### Project conventions
- Testing & checks: verify changes before handing over.

## Handover
Log: `docs/ai-notes/HANDOFF.md` (newest first, signed with agent name and machine).
