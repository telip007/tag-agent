#!/usr/bin/env bash
# Claude Code SessionStart hook. Its stdout becomes session context.
#  1. Installs the repository's git hooks (idempotent), so every agent session
#     runs with the same commit/push gates as humans who ran `make bootstrap`.
#  2. Loads the wiki index and the latest log entries, so agents start from
#     what the project already knows instead of re-deriving it.
set -euo pipefail
cd "${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}"

# Repository-local setting only (documented in CONTRIBUTING.md / AGENTS.md).
if [[ "$(git config --get core.hooksPath || true)" != ".githooks" ]]; then
    git config core.hooksPath .githooks
    echo "Enabled the repository's git hooks (git config core.hooksPath .githooks)."
fi

cat <<'TEXT'
# Project wiki

This repository keeps an LLM-maintained wiki in wiki/ (schema: wiki/SCHEMA.md).
Before working: find relevant pages via the index below and read them.
After working: update affected pages and append to wiki/log.md (use the `wiki` skill).
A Stop hook blocks finishing a turn with code changes but no wiki changes.

TEXT
cat wiki/index.md
echo
echo "## Latest log entries"
grep '^## \[' wiki/log.md | tail -5
