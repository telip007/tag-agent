---
title: Maximum backpressure
summary: Warnings are errors, strict lint, coverage gate, hooks.
updated: 2026-10-17
---

# 0002 Maximum backpressure

## Context

Feedback a tool can give is feedback a human doesn't have to
([Don't waste your back pressure](../sources/dont-waste-your-backpressure.md)).
That holds both for the human learning Swift and for agents working here.

## Decision

Turn every deterministic check to its strictest useful setting. See
[Backpressure setup](../concepts/backpressure-setup.md) for the list.
Checks are never weakened to get a green build. Changing a rule requires the
human's agreement and a decision record.

## Consequences

- Early friction: doc comments on public API, no force unwraps, small
  functions. That friction is the point.
- Nondeterministic checks (type-checking time limits) are excluded.
- Formatter and linter must not contradict each other. Conflicts are resolved
  in favour of swift-format and recorded as gotchas.
