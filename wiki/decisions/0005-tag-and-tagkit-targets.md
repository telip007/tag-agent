---
title: Tag and TagKit targets
summary: A thin executable over a testable library.
updated: 2026-10-18
---

# 0005 Tag and TagKit targets

## Context

The coverage gate ([backpressure setup](../concepts/backpressure-setup.md))
starts enforcing as soon as `Tests/` exists. Executable targets are awkward to
import from tests, and the agent's logic (the loop, model access, tools) is
what needs testing.

## Decision

[Package.swift](../../Package.swift) has two targets:

- `Tag` (executable, `Sources/Tag/`): `@main`, argument parsing, and wiring
  the agent to the UI. Depends on `TagKit`, ArgumentParser and Stipple.
- `TagKit` (library, `Sources/TagKit/`): the agent and, since
  [0008](0008-stipple-terminal-ui.md), its terminal UI. Depends on the
  [OpenRouter SDK](../concepts/openrouter-sdk.md) and Stipple.

Both use the same strict compiler settings.

## Consequences

- Tests go in the `TagKitTests` target and `import TagKit` (plus `OpenRouter`
  for the message types, see [tools](../concepts/tools.md#gotchas)).
- `Tag` should stay small enough that it barely affects coverage.
- SwiftPM rejects a target with no sources, so `Sources/TagKit/` always needs
  at least one file.
