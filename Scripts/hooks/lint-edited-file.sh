#!/usr/bin/env bash
# Claude Code PostToolUse hook for Edit/Write: lint the Swift file that was
# just touched and feed violations straight back to the agent (exit 2).
set -uo pipefail
cd "${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}"

file="$(python3 -I -c 'import json,sys; print(json.load(sys.stdin).get("tool_input", {}).get("file_path", ""))')"
[[ "$file" == *.swift && -f "$file" && "$file" != */Generated/* && "$file" != */.build/* ]] || exit 0

output="$(swift format lint --strict "$file" 2>&1)"
if command -v swiftlint >/dev/null; then
    output+=$'\n'"$(swiftlint lint --strict --quiet "$file" 2>&1)"
else
    echo "SwiftLint is not installed; only swift-format ran. Install it with 'make bootstrap'." >&2
fi
if [[ -n "${output//[[:space:]]/}" ]]; then
    printf 'Lint violations in %s (run `make fix` for formatting):\n%s\n' "$file" "$output" >&2
    exit 2
fi
