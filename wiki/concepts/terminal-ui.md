---
title: Terminal UI
summary: How the full-screen workspace is built on Stipple: the design history, the agent's event seam, the observable session and its blocks, the panes and keys, why it runs on the main actor, and how it is tested.
updated: 2026-10-18
---

# Terminal UI

The chat UI is a [Stipple](https://github.com/telip007/stipple) view
("SwiftUI for the terminal", a Swift port of Ink). Before that, the agent
wrote raw ANSI escapes with `print` and read lines with `readLine`. Why
Stipple, and why the views live in `TagKit`:
[0008](../decisions/0008-stipple-terminal-ui.md).

## Design

The UI is a full-screen workspace (alternate screen): the conversation in a
pane on the left, a **session** panel on the right, a boxed input below, and a
footer with key hints and the agent's current activity.

```text
╭─ tag ──────────────────────────────╮╭─ session ──────────╮
│ ▌ fix the failing parser test      ││ DeepSeek V4.1 Flash│
│                                    ││ ━━━━━━━━━━━━━  12% │
│   Looking at it.                   ││ 124k/1M tokens     │
│   ▸ 3 tools · 4.2s  search · read  ││ $0.0031 · 4m 12s   │
│   ┌ Sources/Parser.swift ── +2 −1 ┐ ││ files              │
│   │ - let flag = "--verbose"      │ ││ Parser.swift +2 −1 │
│   └───────────────────────────────┘ ││                    │
╰────────────────────────────────────╯╰────────────────────╯
╭──────────────────────────────────────────────────────────╮
│ › ask anything                                           │
╰──────────────────────────────────────────────────────────╯
 esc browse · ^p commands · tab panel        ⠋ bash  swift test
```

How it got here (all on 2026-10-18), so the next redesign doesn't repeat it:

1. A plain inline REPL with an amber accent and a ` TAG ` badge: flat and
   cramped next to current agent CLIs.
2. A copy of Claude Code's layout (header, rules around the input, a status
   bar) with a pixel mascot: rejected as a copy, and the mascot, Claude's body
   in a hat, as too similar to Claude's.
3. Three sketched directions themed on Islamic and Ottoman terms: rejected.
   Names in the UI are plain words; theming by vocabulary reads as a gimmick.
4. Research into 2026 agent CLIs: they are full-screen apps, not REPLs. Amp
   went fullscreen with mouse support, overlays and clickable buttons; Toad
   redraws only what changed and lets you interact with past output; Crush has
   a split-pane layout and a diff view; Warp groups output into blocks. Of
   three full-screen sketches, the workspace with a side panel was chosen.

What stayed from the earlier rounds: the gold accent (`Theme.accent`),
turquoise for code (`Theme.tile`), light Markdown in replies, type-ahead,
input history, the double Ctrl-C quit and tool summaries.

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
- `.replyDelta(String)` for each piece of the model's text as it streams in,
  then `.reply(String)` with all of it,
- `.toolStarted(name:arguments:)` before a tool runs, and
  `.toolFinished(name:arguments:output:failed:)` after it, with what the model
  sees; `failed` is set for an unknown tool or a thrown error.

### ChatSession: the state

[`ChatSession`](../../Sources/TagKit/ChatSession.swift) is a
`@MainActor @Observable` class. `handle(_:)` turns events into:

- `transcript`, [`TranscriptBlock`](../../Sources/TagKit/Transcript.swift)s
  whose `content` is `user`, `reply`, `tools([ToolRun])` or `edit(FileEdit)`.
  Blocks can change after they appear: a reply grows with each
  `.replyDelta` (the first one sets the activity to `writing`) and `.reply`
  settles it on the full text; tool calls between two replies share
  one tray, which grows while the agent works; each `ToolRun` goes from
  `running` to `succeeded` or `failed` with its duration and output.
- `edit` blocks: a successful `edit_file` call becomes a `FileEdit`, its
  `old_str` against its `new_str` with the lines they share at both ends
  trimmed, so a one-line change in a long snippet shows as one line.
- `files`, lines added and removed per file over the session, for the panel.
- `expanded`, the blocks the user opened (`toggle(_:)`).
- `status`, `activity`/`activityStart`, `start`/`elapsed`, `queued`, `history`.

Input: `submit(_:)` ignores blank text, records the message in `history`, and
either resumes the waiting `nextMessage()` or appends to `queued` while the
agent is busy (type-ahead). `nextMessage()` takes queued messages first, then
suspends on a `CheckedContinuation` until `submit`, `end()` or cancellation.

The clock is injected (`ChatSession(now:)`) so tests can time tools and the
session deterministically. Helpers:
[`ToolSummary`](../../Sources/TagKit/ToolSummary.swift) (the gist of a call's
arguments) and [`InputHistory`](../../Sources/TagKit/InputHistory.swift)
(shell-style ↑/↓).

### ChatView: the workspace

[`ChatView`](../../Sources/TagKit/ChatView.swift) holds the layout and the key
handling; the parts are in
[`WorkspaceParts.swift`](../../Sources/TagKit/WorkspaceParts.swift):

- `pane(title:isActive:)`: a rounded border with the title set into its top
  edge (an `overlay` at `.topLeading`); gold while active.
- `TranscriptPane`: the blocks in a Stipple `ScrollView` anchored to the
  bottom for `.initialOffset` and `.sizeChanges` but not `.alignment`: a short
  conversation starts at the top of the pane (the maintainer's choice, rather
  than a messaging app's bottom-up layout), and once it overflows the view
  follows the newest block. Also `.scrollOnPageKeys()`, so Page Up/Down scroll while the input has
  focus. The `ScrollPosition` lives in `ChatView`: browse mode calls
  `scrollTo(id:)` on the selected block (each block has `.id(block.id)`), and
  leaving it calls `scrollTo(edge: .bottom)`. Once the user scrolls away
  (`isPositionedByUser` and `edge != .bottom`), the footer offers `↓ latest`.
  A scroll indicator takes the rightmost column when the content overflows. `BlockView` draws each: user messages bold after a gold `▌`;
  replies through [`Markdown`](../../Sources/TagKit/Markdown.swift);
  `ToolTray`, one summary line (`▸ 3 tools · 4.2s  read_file · bash`, the `▸`
  red if one failed) that lists every call while running or when expanded,
  with the first six lines of each output; `EditCard`, a bordered diff with
  the path and `+n −m` in its top edge, the first eight lines until expanded.
  The block selected in browse mode gets a tinted background.
- `SessionPanel` (30 columns, hidden below 90): the model, the folder, a
  context gauge (`━`, turquoise, gold past 50%, red past 80%), tokens, cost and
  session time, the files changed and the queued messages.
- The input: a rounded box, gold while the agent waits (`ask anything`), gray
  while it works (`type ahead…`).
- `Footer`: key hints, or a warning (`press ctrl-c again to quit`), on the
  left; the spinner with the current activity and its time on the right.
- `CommandPalette`: an overlay with a `SelectionList` of `PaletteCommand`s.
- Mouse (`renderOptions.mouseReporting`): the wheel scrolls the pane under the
  pointer, a click on a block expands or collapses it, and footer hints and
  palette rows are clickable (`.onTapGesture`). Clicking the input box focuses
  it. Hover (Stipple 0.3.0): a tool tray or diff under the pointer gets the
  selection tint, to show it can be clicked, and a footer hint lights up gold. Footer hints carry their
  action (`Footer.Key`), so the key and the click do the same thing. With
  mouse reporting on, selecting text in the terminal needs Shift (Option in
  some macOS terminals).
- Copy uses OSC 52 (`Clipboard`), which works over SSH and is ignored by
  terminals without it; the view takes a `copy` closure so tests don't write to
  stdout.

### Keys

| Key | What |
| --- | --- |
| Enter | send, or queue while the agent works |
| ↑ / ↓ | previous / next sent message; ↓ past the newest restores the draft |
| Esc | on an empty line: browse the conversation |
| ↑↓ or j/k, Enter, c | while browsing: move, expand or collapse, copy; Esc or typing goes back |
| Page Up / Down | scroll the conversation; the wheel works too |
| Ctrl-P | command palette |
| Tab | show or hide the session panel |
| Ctrl-C | clear the line; on an empty line, press again within 2 s to quit |
| Ctrl-D | quit, on an empty line |

`ChatView.renderOptions` turns on the alternate screen and turns off Stipple's
`exitOnCtrlC`, so Ctrl-C reaches the view's `onKeyPress`. The keys the
`TextField` leaves alone are mapped by the pure `PromptKey` and `BrowseKey`
types. Tab also moves Stipple's focus, harmlessly: the input is the only
focusable view.

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

## Streaming

Replies stream: the text appears as the model writes it instead of all at
once when the reply is complete, so the agent feels responsive even when a
long answer takes many seconds. Every delta changes `transcript`, which
Stipple observes; Stipple's runtime batches the changes in one main-actor turn
and draws at most `RenderOptions.maxFps` (30) frames a second, so a fast model
doesn't redraw the screen per token. Checked live by timing when words of a
long reply first reached the pseudo-terminal: they arrived across many frames.

## Testing

- The agent loop is tested by collecting `AgentEvent`s from a scripted model
  ([AgentTests.swift](../../Tests/TagKitTests/AgentTests.swift)).
- `ChatSession` and `FileEdit` are tested directly with an injected clock
  ([ChatSessionTests.swift](../../Tests/TagKitTests/ChatSessionTests.swift)).
- `ToolSummary` and `InputHistory`:
  [PromptHelpersTests.swift](../../Tests/TagKitTests/PromptHelpersTests.swift).
- Views are rendered with `Stipple.renderToString`, the ANSI codes stripped,
  and compared as text; the whole workspace is rendered at a fixed size with
  `.frame(height:)` and a `terminalSize` environment
  ([ChatViewTests.swift](../../Tests/TagKitTests/ChatViewTests.swift)). Key
  handling can't run there, so the key maps are tested on their own.
- Mouse clicks were checked live in a pseudo-terminal by sending an SGR
  click on a footer hint (`\e[<0;30;30M`, then `m` for the release).
- Looks are checked by rendering a sample session to ANSI, converting it to
  HTML and screenshotting it in a headless browser. Half blocks and some box
  characters render with gaps there, unlike in a terminal.

## Limitations

- **The alternate screen hides the conversation on exit**, as in other
  full-screen tools.
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
  so the accent colour came out wrong on terminals without truecolor. Fixed
  upstream in 0.1.1: the colour depth is detected like chalk's supports-color
  (`RenderOptions.colorDepth`, `nil` detects) and RGB is downsampled; on a
  256-colour terminal it becomes the nearest palette entry. Piped output now has no
  colour unless `FORCE_COLOR` is set.
- **Ctrl-D on an empty line** was swallowed by Stipple 0.1.0's `TextField`
  (readline's delete-forward). Since 0.1.1 an empty field leaves it unhandled,
  so `PromptKey` sees it as end-of-input.
- **The caret went stale after the app changed the text.** Clearing the field
  in `onSubmit` left Stipple 0.1.0's insertion point where it was, drawing the
  placeholder's cursor mid-word. Since 0.1.1 an outside change (clearing,
  history recall) moves the caret to the end of the new text.
- These three were found while building this UI and fixed in Stipple itself
  ([0008](../decisions/0008-stipple-terminal-ui.md)).
- **Scrolling and the mouse came from Stipple 0.2.0**, built for this
  workspace: `ScrollView`, `ScrollPosition`, `.defaultScrollAnchor`,
  `.scrollOnPageKeys()`, `.id(_:)`, `.onTapGesture` and
  `RenderOptions.mouseReporting`. Taps and wheel hit-testing need the
  alternate screen. Stipple 0.3.0 added focus on click, double-click and
  `.onHover` (motion reporting is only switched on while a view has a hover
  handler). `Package.swift` requires 0.3.0.
- **SwiftLint's `type_body_length` (200 lines)** applies to `ChatView` and to
  test suites. Helpers live in an `extension ChatView` in the same file
  (`fileprivate`, so they still reach the `private` state), and the key-map
  tests are their own suite.
