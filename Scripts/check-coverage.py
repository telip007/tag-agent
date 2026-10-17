#!/usr/bin/env python3
"""Fail if line coverage of hand-written sources is below a threshold.

Usage: check-coverage.py <llvm-cov-export.json> <min-percent> [source-dir ...]

Reads the JSON written by `swift test --enable-code-coverage` (its path is
printed by `swift test --show-codecov-path`). Only files under the given
source directories count; `Generated/` directories are always skipped.
"""

import json
import os
import sys


def main():
    report, minimum, *roots = sys.argv[1:]
    roots = [os.path.abspath(r) + os.sep for r in (roots or ["Sources"])]
    with open(report) as f:
        files = json.load(f)["data"][0]["files"]

    covered = total = 0
    rows = []
    for entry in files:
        path = entry["filename"]
        if not any(path.startswith(r) for r in roots) or f"{os.sep}Generated{os.sep}" in path:
            continue
        lines = entry["summary"]["lines"]
        covered += lines["covered"]
        total += lines["count"]
        rows.append((lines["percent"], os.path.relpath(path), lines["covered"], lines["count"]))

    if total == 0:
        print("coverage: no hand-written sources found, nothing to check")
        return

    for percent, path, hit, count in sorted(rows):
        print(f"  {percent:6.1f}%  {hit:4}/{count:<4}  {path}")
    percent = 100 * covered / total
    print(f"coverage: {percent:.1f}% of {total} lines (minimum {minimum}%)")
    if percent < float(minimum):
        sys.exit(f"coverage: below the {minimum}% minimum")


if __name__ == "__main__":
    main()
