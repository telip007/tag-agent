---
title: Conventional Commits
summary: Commit messages and PR titles use the same Conventional Commits format as the SDK; no release tooling yet.
updated: 2026-10-18
---

# 0007 Conventional Commits

## Context

Tag Agent went public next to its SDK, swift-openrouter, which already uses
[Conventional Commits](https://www.conventionalcommits.org/) and derives its
versions and changelog from them with release-please (the SDK's decision 0010).
One commit format across both repositories is easier for contributors and
agents. Tag Agent has nothing releasable yet.

## Decision

- Commit messages and PR titles follow Conventional Commits, with the SDK's
  types and checker: [Scripts/check-commit-message.py](../../Scripts/check-commit-message.py),
  run by the `commit-msg` hook ([.githooks/commit-msg](../../.githooks/commit-msg))
  and by a `pr-title` job in [CI](../../.github/workflows/ci.yml).
- PRs are squash-merged, so the PR title becomes the commit on `main`.
- **No release-please yet.** Add it when there is something to release; the
  history will already be in the right format for it.

## Consequences

- Commits before this decision (the first three) don't follow the format.
- Choose the type by the effect on users of the agent (`feat`, `fix`) or on
  contributors (`ci`, `docs`, `test`, `refactor`, `chore`).
