#!/usr/bin/env python3
"""Structural lint for wiki/ (see wiki/SCHEMA.md).

Checks:
  - every page has frontmatter with `title`, `summary` and `updated: YYYY-MM-DD`
  - every page is listed in wiki/index.md
  - every relative link (to wiki pages or repository files) resolves
  - every wiki/log.md entry heading matches `## [YYYY-MM-DD] <op> | <title>`
  - no private data: absolute home paths or email addresses (wiki/ is public)
  - with --staged: no already-committed file under wiki/raw/ is modified

Usage: wiki-lint.py [--staged]
"""

import os
import re
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
WIKI = os.path.join(ROOT, "wiki")
SPECIAL = {"index.md", "log.md", "SCHEMA.md"}
LOG_OPS = {"ingest", "query", "update", "decision", "lint"}
LINK = re.compile(r"(?<!!)\[[^\]]*\]\(([^)\s]+)\)")
DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
PRIVATE = [
    (re.compile(r"(/Users/|/home/|C:\\Users\\)[^/\s]+"), "absolute home path"),
    (re.compile(r"[\w.+-]+@[\w-]+\.[\w.-]+"), "email address"),
]
LOG_ENTRY = re.compile(r"^## \[(\d{4}-\d{2}-\d{2})\] ([a-z]+) \| .+$")


def pages():
    for directory, subdirs, files in os.walk(WIKI):
        subdirs[:] = [d for d in subdirs if d != "raw"]
        for name in sorted(files):
            if name.endswith(".md"):
                yield os.path.join(directory, name)


def all_markdown():
    for directory, _, files in os.walk(WIKI):
        for name in sorted(files):
            if name.endswith(".md"):
                yield os.path.join(directory, name)


def frontmatter(text):
    if not text.startswith("---\n"):
        return None
    end = text.find("\n---\n", 4)
    if end == -1:
        return None
    fields = {}
    for line in text[4:end].splitlines():
        key, _, value = line.partition(":")
        fields[key.strip()] = value.strip()
    return fields


def strip_code(text):
    text = re.sub(r"```.*?```", "", text, flags=re.S)
    return re.sub(r"`[^`\n]*`", "", text)


def check_links(path, text, errors):
    for target in LINK.findall(strip_code(text)):
        if re.match(r"^[a-z]+:", target) or target.startswith("#"):
            continue
        resolved = os.path.normpath(os.path.join(os.path.dirname(path), target.split("#")[0]))
        if not os.path.exists(resolved):
            errors.append(f"{rel(path)}: broken link -> {target}")


def check_private(path, text, errors):
    for number, line in enumerate(text.splitlines(), 1):
        for pattern, what in PRIVATE:
            if pattern.search(line):
                errors.append(f"{rel(path)}:{number}: {what} in a public wiki")


def check_log(errors):
    path = os.path.join(WIKI, "log.md")
    for number, line in enumerate(open(path), 1):
        if not line.startswith("## "):
            continue
        match = LOG_ENTRY.match(line.rstrip("\n"))
        if not match or match.group(2) not in LOG_OPS:
            ops = "|".join(sorted(LOG_OPS))
            errors.append(f"wiki/log.md:{number}: expected '## [YYYY-MM-DD] <{ops}> | <title>'")


def check_raw_immutable(errors):
    out = subprocess.run(
        ["git", "diff", "--cached", "--name-status", "--", "wiki/raw"],
        cwd=ROOT, capture_output=True, text=True, check=True,
    ).stdout
    for line in out.splitlines():
        status, _, name = line.partition("\t")
        if status[0] in "MDR":
            errors.append(f"{name}: wiki/raw/ is immutable; add a new file instead of changing this one")


def rel(path):
    return os.path.relpath(path, ROOT)


def main():
    errors = []
    index = open(os.path.join(WIKI, "index.md")).read()
    indexed = {os.path.normpath(os.path.join(WIKI, t.split("#")[0])) for t in LINK.findall(index)}

    for path in all_markdown():
        check_private(path, open(path).read(), errors)

    for path in pages():
        text = open(path).read()
        check_links(path, text, errors)
        if os.path.basename(path) in SPECIAL and os.path.dirname(path) == WIKI:
            continue
        fields = frontmatter(text)
        if fields is None:
            errors.append(f"{rel(path)}: missing frontmatter (title, summary, updated)")
        else:
            for key in ("title", "summary", "updated"):
                if not fields.get(key):
                    errors.append(f"{rel(path)}: frontmatter is missing '{key}'")
            if fields.get("updated") and not DATE.match(fields["updated"]):
                errors.append(f"{rel(path)}: 'updated' must be YYYY-MM-DD")
        if path not in indexed:
            errors.append(f"{rel(path)}: not listed in wiki/index.md")

    check_log(errors)
    if "--staged" in sys.argv:
        check_raw_immutable(errors)

    for error in errors:
        print(f"wiki-lint: {error}", file=sys.stderr)
    if errors:
        sys.exit(1)
    print(f"wiki-lint: ok ({sum(1 for _ in pages())} pages)")


if __name__ == "__main__":
    main()
