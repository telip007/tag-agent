---
title: Agent workflow
summary: How hooks, skills, AGENTS.md and the wiki make every agent session follow the same rules.
updated: 2026-10-17
---

# Agent workflow

Goal: a fresh agent session, with any model and any tool, starts from what the
project knows and leaves it knowing more, without the human repeating
instructions. Rationale: [0004 LLM-maintained wiki](../decisions/0004-llm-wiki.md).

## Layers of instruction

1. **[AGENTS.md](../../AGENTS.md)** is the portable contract for every agent
   (Codex, Cursor, Claude, …): commands, rules, wiki duties.
   [CLAUDE.md](../../CLAUDE.md) imports it and adds Claude Code specifics.
2. **Skills** in `.claude/skills/` are loaded on demand by Claude Code:
   - [wiki](../../.claude/skills/wiki/SKILL.md): query, update, ingest, lint.
   - [backpressure](../../.claude/skills/backpressure/SKILL.md): the
     `make check` loop and the "never weaken a check" rule.
3. **Hooks** in [.claude/settings.json](../../.claude/settings.json) are
   committed, so they apply to every Claude Code session in a trusted checkout:
   - `SessionStart` → [session-start.sh](../../Scripts/hooks/session-start.sh):
     sets `core.hooksPath=.githooks` (git hooks auto-install) and injects
     `wiki/index.md` plus the last log entries into context.
   - `PostToolUse` (Edit/Write) → [lint-edited-file.sh](../../Scripts/hooks/lint-edited-file.sh):
     swift-format and SwiftLint on the edited file; violations go back to the
     agent (exit 2).
   - `Stop` → [wiki-guard.sh](../../Scripts/hooks/wiki-guard.sh): blocks
     ending a turn when non-wiki files changed and `wiki/` didn't, once per
     distinct change set (fingerprint stored in `.git/wiki-guard-last`), so
     an agent can still finish after saying "nothing to record".
4. **Git hooks and CI** enforce structure for everyone, agents without hook
   support included.

## Gotchas

- Claude Code only runs project hooks after the folder is trusted. The
  first session in a new clone asks.
- The git pre-commit hook enforces wiki *structure*, not wiki *updates*. Human
  commits shouldn't be forced to touch the wiki. Keeping it current is the
  agents' job (the Stop hook).
- The Stop hook ignores `Package.resolved`, `Packages/` (submodule pointer)
  and Xcode user state, which carry no knowledge.
