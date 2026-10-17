#!/usr/bin/env bash
# Claude Code Stop hook: an agent may not end its turn with uncommitted
# project changes while wiki/ is untouched. It blocks once per distinct set of
# changes, so an agent that decides "nothing worth recording" can finish by
# trying again; the reason it was given asks it to say so explicitly.
set -euo pipefail
cd "${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}"

input="$(cat)"
if [[ "$(printf '%s' "$input" | python3 -I -c 'import json,sys; print(json.load(sys.stdin).get("stop_hook_active", False))')" == "True" ]]; then
    exit 0
fi

# Changes that may carry knowledge worth recording.
pathspec=(. ':!wiki' ':!Package.resolved' ':!Packages' ':!*.xcuserstate')
changed="$(git status --porcelain --untracked-files=all -- "${pathspec[@]}")"
[[ -z "$changed" ]] && exit 0
[[ -n "$(git status --porcelain --untracked-files=all -- wiki)" ]] && exit 0

fingerprint="$({ git diff HEAD -- "${pathspec[@]}"; git ls-files --others --exclude-standard -- "${pathspec[@]}"; } | shasum | cut -d' ' -f1)"
state="$(git rev-parse --git-path wiki-guard-last)"
[[ -f "$state" && "$(cat "$state")" == "$fingerprint" ]] && exit 0
echo "$fingerprint" > "$state"

files="$(printf '%s\n' "$changed" | head -15 | sed 's/^/  /')"
python3 -I -c 'import json,sys; print(json.dumps({"decision": "block", "reason": sys.argv[1]}))' \
"These files changed but wiki/ did not:
$files

Use the \`wiki\` skill: update the pages this work affects (decisions, gotchas, how things work) and append an entry to wiki/log.md. If there is genuinely nothing worth recording, say so in one sentence and stop again."
