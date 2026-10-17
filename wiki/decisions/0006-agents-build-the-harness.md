---
title: Agents build the harness
summary: After the hand-written first loop, agents write Sources/ code too.
updated: 2026-10-17
---

# 0006 Agents build the harness

Supersedes [0001](0001-hand-written-agent-code.md).

## Context

Under 0001 the maintainer wrote the first version of the agent by hand,
following Thorsten Ball's "How to build an agent" (ampcode.com/notes): the
`Agent` loop, the `ChatModel` seam and the `Tag` entry point
([0005](0005-tag-and-tagkit-targets.md)). The goal of that phase, understanding
how the loop works, was met.

## Decision

Agents may write and change code under `Sources/` like anywhere else in the
repository. All other rules stay: `make check` must pass, checks are never
weakened, and the wiki is kept up to date.

## Consequences

- AGENTS.md no longer has the "explain, don't write" rule.
- The wiki still records what was learned (concepts, mistakes, design
  choices), whoever wrote the code.
