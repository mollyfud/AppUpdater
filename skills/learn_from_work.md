# Skill: Learn from Work (`/learn`)

Interactive skill for Claude Code and Antigravity sessions across projects.

## Purpose
Enables agents and Molly to reflect on work just performed, distill non-obvious traps, gotchas, or recurring conventions, and propose structured additions to either:
1. **The Global Rules Bank** (`Switchboard/global-rules/GLOBAL_RULES.md`, synced to `~/.claude/CLAUDE.md` and `~/.gemini/AGENTS.md`).
2. **Project-specific rules** (`<repo>/AGENTS.md` under `### Project conventions`).

---

## When to Use
- When Molly types `/learn` or says "what did we learn from this work?"
- At the end of a non-trivial session or debugging investigation where a trap was uncovered.
- When an automated reflection prompt is triggered.

---

## Quality Bar & Threshold
- **High bar:** Default to proposing **zero** rules unless a concrete, reusable pitfall or convention was encountered.
- **Do NOT propose:**
  - Standard, obvious best practices (e.g. "write tests", "handle errors", "keep code clean").
  - One-off quirks or typos specific to a single typo or temporary outage.
- **DO propose:**
  - Non-obvious UI conventions (e.g. "Color schemes & UI: Always verify UI components in both light and dark themes").
  - Platform/tool quirks (e.g. Windows path escaping differences, strict shell whitelist execution constraints).
  - Project architectural boundaries or contract invariants.

---

## Scope Determination
- **`global`:** Rules that apply to every repository and workflow Molly works on.
  - Target: `Switchboard/global-rules/GLOBAL_RULES.md` under `## 5. Learned Conventions & Guidelines`.
  - Effect: When committed, Switchboard spokes sync it to `~/.claude/CLAUDE.md` and `~/.gemini/AGENTS.md`.
- **`project`:** Rules that apply only to this specific codebase.
  - Target: `<repo>/AGENTS.md` under `### Project conventions` (or `## Rules for this project`).

---

## Interactive Protocol
When invoked in an interactive session:
1. **Review Recent Work:**
   - Run `git diff` or review recent commit logs.
   - Review recent handover log entries in `docs/ai-notes/HANDOFF.md`.
2. **Identify Pitfalls:**
   - Did any test fail unexpectedly due to a missing requirement?
   - Did any UI element break in a specific mode or screen size?
   - Did any contract or schema require manual synchronization across components?
3. **Formulate Candidate Rules:**
   - Formulate 0-2 candidate rules with:
     - **Scope:** `global` or `project`.
     - **Rule:** Concise, imperative instruction (e.g., `- **UI Contrast:** Always test widgets against both light and dark backgrounds`).
     - **Rationale:** 1-2 sentences explaining what was observed and why the rule prevents future errors.
4. **Present to Molly:**
   - Ask Molly for approval before modifying any rules file.
   - Example prompt:
     > "We observed that flutter widgets lacked dark mode borders. I propose adding this rule to **Global Rules Bank**:
     > `- **Color schemes & UI:** Always verify UI components and styling in both light and dark themes.`
     > Would you like me to apply this?"
5. **Apply on Confirmation:**
   - If `project`: Append to `<repo>/AGENTS.md` and commit locally.
   - If `global`: Append to `Switchboard/global-rules/GLOBAL_RULES.md`, sync to `~/.claude/CLAUDE.md` and `~/.gemini/AGENTS.md`, and commit in Switchboard.
