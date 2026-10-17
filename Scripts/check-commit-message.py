#!/usr/bin/env python3
"""Validates a Conventional Commits header (https://www.conventionalcommits.org).

Usage:
  check-commit-message.py <commit-msg-file>   # git commit-msg hook
  check-commit-message.py --title "<text>"    # e.g. a pull request title
"""

import re
import sys

TYPES = ("feat", "fix", "perf", "revert", "docs", "deps", "refactor", "test", "build", "ci", "chore", "style")
HEADER = re.compile(rf"^(?:{'|'.join(TYPES)})(?:\([a-z0-9][a-z0-9/._-]*\))?!?: \S.{{0,98}}$")
EXEMPT = re.compile(r"^(Merge |Revert \"|fixup! |squash! |amend! )")

HELP = f"""Expected a Conventional Commits header, e.g.
  feat(tools): add a code_search tool
  fix: keep stdin away from bash commands
  feat!: rename ToolDefinition.function
Types: {", ".join(TYPES)}. Add `!` (or a `BREAKING CHANGE:` footer) for
breaking changes. Header ≤ 100 characters. See CONTRIBUTING.md."""


def main():
    if sys.argv[1:2] == ["--title"]:
        header = " ".join(sys.argv[2:]).strip()
    else:
        with open(sys.argv[1]) as f:
            lines = [line for line in f.read().splitlines() if not line.startswith("#")]
        header = next((line for line in lines if line.strip()), "")
    if EXEMPT.match(header) or HEADER.match(header):
        return
    sys.exit(f"Invalid commit message header: {header!r}\n\n{HELP}")


if __name__ == "__main__":
    main()
