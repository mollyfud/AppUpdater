# Cross-project Inbox for AppUpdater

Work that agents in *other* projects (or on another machine) left for this project.
Rules: Section 4 of Molly's global working agreement (`~/.claude/CLAUDE.md` = `~/.gemini/AGENTS.md`).

### 2026-10-20 - from TennisSpark / Claude Code on DADSLAPTOP: get the repo ready to go public, then tag a release
- **Ask:** (1) remove the `*.workers.dev` Worker URL from `docs/ai-notes/HANDOFF.md` and `PLAN.md` (say "the gateway URL, see Switchboard/updater config" instead); it is the only identifying detail. Molly decides separately whether to accept it staying in git history. (2) push `main` (it is ahead of origin) and tag a release (e.g. `v0.2.0`) so apps can pin a git dependency to it.
- **Why:** the repo is private, so GitHub CI and the Railway Docker build can't resolve the `app_updater_flutter` path dependency; TennisSpark's `app` job fails at `flutter pub get`. I audited the 29 tracked files and the full history on 2026-10-20: no secrets, tokens, emails or account ids. Once Molly makes the repo public, TennisSpark switches to `git: url: https://github.com/mollyfud/AppUpdater.git, path: packages/app_updater_flutter, ref: <tag>`. Other apps using the path dependency have the same problem.
- **Urgency:** soon


