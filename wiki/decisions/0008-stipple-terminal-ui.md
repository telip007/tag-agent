---
title: Stipple for the terminal UI
summary: The chat UI is a Stipple view instead of print/readLine with raw ANSI escapes, and the views live in TagKit so they can be tested.
updated: 2026-10-18
---

# 0008 Stipple for the terminal UI

## Context

The first loop printed with `print`, read with `readLine` and coloured its
labels with hand-written ANSI escapes inside `Agent`. That mixed formatting
into the loop and left no room for a live area: a spinner while the model
thinks, an input line that stays put, a status line below it. Doing that by
hand means raw mode, cursor movement and terminal restore on every exit path.

[Stipple](https://github.com/telip007/stipple) is a Swift port of Ink with a
SwiftUI-shaped API: `View`, `@State`, `TextField`, `ProgressView`, `Static`
scrollback, raw-mode input, and terminal restore on exit, error and crash.

## Decision

- The UI is built with Stipple, added in [Package.swift](../../Package.swift)
  (`from: "0.3.0"`, product `Stipple`) for `Tag`, `TagKit` and `TagKitTests`.
- `Agent` emits `AgentEvent`s and formats nothing; `ChatSession` holds the
  UI state and `ChatView` renders it ([terminal UI](../concepts/terminal-ui.md)).
- **`ChatSession` and `ChatView` live in `TagKit`, not `Tag`.** Tests can't
  import an executable target, and the views have logic worth testing (what
  shows when, input hand-off). This refines
  [0005](0005-tag-and-tagkit-targets.md): `Tag` keeps argument parsing and
  wiring, `TagKit` owns the agent *and* its UI.

- The look follows the maintainer's brief, *a simple look that reveals
  hidden aha moments; retro but state of the art*: a quiet layout after
  current agent CLIs, a distinctive palette, and features (history,
  type-ahead, turn costs, the warming context figure) that show up when used ([design intent](../concepts/terminal-ui.md#design-intent)).

## Consequences

- `Agent` is `@MainActor`, next to the UI it reports to.
- Stipple bugs surface here first (truecolor-only RGB, Ctrl-D in an empty
  `TextField`) and are fixed upstream, then picked up by bumping the version.
- Views are tested with `Stipple.renderToString`.
- Piping messages on stdin no longer works; input needs a terminal.
- Stipple is pre-1.0, so minor releases may break the API.
