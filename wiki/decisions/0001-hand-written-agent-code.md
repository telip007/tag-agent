---
title: Agent code is written by hand
summary: Agents teach and review; the human writes Sources/Tag.
updated: 2026-10-17
---

# 0001 Agent code is written by hand

## Context

Tag Agent is a learning project: the point is to understand how a coding agent
harness works by building one by hand, not just to end up with one.

## Decision

Agents do **not** write or modify code under `Sources/` unless the human
explicitly asks for that specific change in the current message. Agents
may freely work on tooling, configuration, scripts, CI, the wiki and the SDK
submodule, and should explain concepts, review the human's code and point to
relevant APIs and docs.

## Consequences

- Reviews and explanations are the main way agents contribute to `Sources/`.
- The SDK ([OpenRouter SDK](../concepts/openrouter-sdk.md)) was built by an
  agent precisely so the harness itself stays hand-written. Its stream
  accumulator and tool helpers are optional conveniences. Re-implementing
  them by hand is a valid exercise.
