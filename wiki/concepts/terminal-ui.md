---
title: Terminal UI
summary: How the chat UI is built on Stipple: the design intent, the agent's event seam, the observable session, the view and its hidden keys, why it runs on the main actor, and how it is tested.
updated: 2026-10-18
---

# Terminal UI

The chat UI is a [Stipple](https://github.com/telip007/stipple) view
("SwiftUI for the terminal", a Swift port of Ink). Before that, the agent
wrote raw ANSI escapes with `print` and read lines with `readLine`. Why
Stipple, and why the views live in `TagKit`:
[0008](../decisions/0008-stipple-terminal-ui.md).

## Design intent

The maintainer's brief: *a simple look that reveals hidden aha moments; retro
but state of the art.*

- **Simple look.** At rest it is a prompt (`›`) and one status line, nothing
  else. No help text, no boxes. Lines in the transcript have one accent colour
  and dim secondary text.
- **Retro.** One accent colour, amber phosphor (RGB 255,176,0, `Theme.accent`),
  as on old terminals. A ` TAG ` badge opens the session, a braille spinner
  shows work, `▰▱` cells show context use.
- **Hidden aha moments.** Features show up when you use them, not before:
  ↑ brings back your last message, typing while the agent works queues the
  message (`type ahead…`, `N queued`), a slow tool call shows how long it took,
  each turn ends with what it cost, the context meter warms from green to
  amber to red, and the status bar narrows with the terminal instead of
  wrapping.

## Three pieces

```text
Agent ──AgentEvent──▶ ChatSession ──observed by──▶ ChatView
  ▲                        │
  └──── nextMessage() ◀────┘ ◀── submit(_:) on Enter
```

### Agent: events, no formatting

[`Agent`](../../Sources/TagKit/Agent.swift) reports through
`output: (AgentEvent) -> Void` and reads input with
`getUserMessage: () async -> String?` (`nil` ends the session). The events:

- `.status(StatusLine)` before each prompt ([status line](tools.md#the-status-line)),
- `.thinking` before each model call,
- `.reply(String)` for the model's text,
- `.toolStarted(name:arguments:)` before a tool runs, and
  `.toolFinished(name:arguments:failed:)` after it; `failed` is set for an
  unknown tool or a thrown error.

### ChatSession: the state

[`ChatSession`](../../Sources/TagKit/ChatSession.swift) is a
`@MainActor @Observable` class. `handle(_:)` turns events into:

- `transcript`, finished `TranscriptEntry`s whose `content` is one of:
  - `banner(model:folder:)`, added on the first status,
  - `user`, `agent`,
  - `tool(name:summary:failed:duration:)`, where `duration` is only set when
    the call took at least a second (`noticeableDuration`),
  - `turnSummary`, added when the next status ends a turn:
    `2 tools · 4.1s · $0.0031` (tool count, wall time, cost of that turn).
- `status`, the latest `StatusLine`.
- `activity` and `activityStart` (`"thinking"`, or the tool name and its
  summary), which drive the spinner and its elapsed time.
- `queued` and `history`.

Input: `submit(_:)` ignores blank text, records the message in `history`, and
either resumes the waiting `nextMessage()` or appends to `queued` while the
agent is busy (type-ahead). `nextMessage()` takes queued messages first, then
suspends on a `CheckedContinuation` until `submit`, `end()` or cancellation.
A message enters the transcript when the agent takes it, not when typed.

The clock is injected (`ChatSession(now:)`) so tests can time turns and tool
calls deterministically.

Helpers:

- [`ToolSummary`](../../Sources/TagKit/ToolSummary.swift) shows the gist of a
  call's JSON arguments: the `command`, `path` or `pattern` value (else the
  first string value), newlines as ` ⏎ `, at most 60 characters. `swift build`
  instead of `{"command":"swift build"}`.
- [`InputHistory`](../../Sources/TagKit/InputHistory.swift) walks `history`
  shell-style: the first ↑ saves the line being typed, ↓ past the newest
  message restores it.

### ChatView: the look

[`ChatView`](../../Sources/TagKit/ChatView.swift):

- `Static(transcript)` writes each finished line once into the terminal's
  scrollback. User messages sit at the margin after an amber `›`; agent text
  and tool lines hang two columns in. Tool lines start with an amber `▸`, or
  a red `✗` when they failed, then the name, the dim summary and the duration.
  The turn summary is a dim `─` line.
- The live area: an `ActivityLine` (braille spinner in a `TimelineView` at
  80 ms, the activity, elapsed time after a second), the `›` prompt with a
  `TextField` (amber when the agent waits, gray with the placeholder
  `type ahead…` while busy), then the `StatusBar`.
- `StatusBar` styles the status line's fields (`StatusLine.folder`,
  `model.name`, `contextUsage`, `money`) and adds an 8-cell `▰▱` meter from
  `contextFraction`: green under 50%, amber under 80%, red above. It reads
  `@Environment(\.terminalSize)` and drops the folder, then the model, then
  the meter when the line doesn't fit. With messages queued it shows
  `N queued` in amber.
- `.task` runs the agent and calls `exit()` when the loop ends, or
  `exit(throwing:)` with its error.

### Keys

| Key | What |
| --- | --- |
| Enter | send, or queue while the agent works |
| ↑ / ↓ | previous / next sent message; ↓ past the newest restores the draft |
| Ctrl-C | clear the line; on an empty line, press again within 2 s to quit |
| Ctrl-D | quit, on an empty line |

`ChatView.renderOptions` turns off Stipple's `exitOnCtrlC`, so Ctrl-C reaches
the view's `onKeyPress`. Arrow keys and Ctrl-D are handled there too, because
the `TextField` leaves them unhandled.

[Tag.swift](../../Sources/Tag/Tag.swift) wires everything up: a
`ChatSession`, an `Agent` with `output: session.handle` and
`getUserMessage: session.nextMessage`, then
`Stipple.run(ChatView(...), options: ChatView.renderOptions)`.

## Why the main actor

Stipple views and state live on the main actor, so `ChatSession.handle` is a
`@MainActor` method. The old `output` was a nonisolated synchronous closure,
and a main-actor function can't be passed where one is expected. Rather than
hop with a fire-and-forget `Task { @MainActor in … }` per event (no guarantee
the UI has the event before the loop moves on), `Agent` became `@MainActor`
too. It only awaits the model and the tools, so the UI stays live while they
run.

`AsyncParsableCommand.run()` is nonisolated, so `Tag` calls a `@MainActor`
static helper (`chat()`) that builds everything and runs the view.

## Testing

- The agent loop is tested by collecting `AgentEvent`s from a scripted model
  ([AgentTests.swift](../../Tests/TagKitTests/AgentTests.swift)); no terminal
  is involved.
- `ChatSession` is tested directly with an injected clock: feed events, call
  `submit`/`end`, check the transcript, the queue and what `nextMessage()`
  returns ([ChatSessionTests.swift](../../Tests/TagKitTests/ChatSessionTests.swift)).
- `ToolSummary` and `InputHistory` are plain functions and are tested as such
  ([PromptHelpersTests.swift](../../Tests/TagKitTests/PromptHelpersTests.swift)).
- Views are rendered to a string with `Stipple.renderToString`, the ANSI
  codes stripped, and compared as text, without a TTY
  ([ChatViewTests.swift](../../Tests/TagKitTests/ChatViewTests.swift)). Key
  handling can't run there (`renderToString` runs no handlers), so the key
  mapping lives in the pure `PromptKey` type and is tested on its own, as is
  `StatusBar.fields(for:queued:width:)`.
- Checked by hand in a pseudo-terminal: banner, status bar, spinner, Ctrl-C
  clearing the line and the double Ctrl-C quit.

## Limitations

- **No piped input.** Input comes from Stipple's raw-mode keyboard handling,
  so `echo "hi" | swift run Tag`, which `readLine` allowed, no longer works. A
  non-interactive mode would need its own input path.
- **Quitting** is `exit()` from a key or from the agent's loop ending;
  `Stipple.run` returns and the process ends. Should the view's task be
  cancelled while the agent waits for input, `nextMessage()` returns `nil`
  and the session ends (tested), so the loop stops cleanly.

## Gotchas

- **A public `@Observable` class needs `public import Observation`** under
  `InternalImportsByDefault`: the macro expands into public members that use
  `Observation` types.
- **`@MainActor` closures don't convert to nonisolated synchronous ones.**
  Passing `session.handle` as the old `(String) -> Void` `output` fails to
  compile; see [why the main actor](#why-the-main-actor).
- **Stipple 0.1.0 always emitted RGB colours as truecolor**, despite its docs,
  so the amber accent came out wrong on terminals without truecolor. Fixed
  upstream in 0.1.1: the colour depth is detected like chalk's supports-color
  (`RenderOptions.colorDepth`, `nil` detects) and RGB is downsampled; on a
  256-colour terminal the amber becomes palette 214. Piped output now has no
  colour unless `FORCE_COLOR` is set.
- **Ctrl-D on an empty line** was swallowed by Stipple 0.1.0's `TextField`
  (readline's delete-forward). Since 0.1.1 an empty field leaves it unhandled,
  so `PromptKey` sees it as end-of-input.
- **The caret went stale after the app changed the text.** Clearing the field
  in `onSubmit` left Stipple 0.1.0's insertion point where it was, drawing the
  placeholder's cursor mid-word. Since 0.1.1 an outside change (clearing,
  history recall) moves the caret to the end of the new text.
- These three were found while building this UI and fixed in Stipple itself
  ([0008](../decisions/0008-stipple-terminal-ui.md)); `Package.swift` requires
  0.1.1.
