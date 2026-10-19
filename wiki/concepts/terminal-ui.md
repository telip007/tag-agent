---
title: Terminal UI
summary: How the full-screen workspace is built on Stipple: the design history, the welcome cat, the agent's event seam, the observable session and its blocks, the panes and keys, why it runs on the main actor, and how it is tested.
updated: 2026-10-19
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
3. Three sketched directions themed on vocabulary: rejected.
   Names in the UI are plain words; theming by vocabulary reads as a gimmick.
4. Research into 2026 agent CLIs: they are full-screen apps, not REPLs. Amp
   went fullscreen with mouse support, overlays and clickable buttons; Toad
   redraws only what changed and lets you interact with past output; Crush has
   a split-pane layout and a diff view; Warp groups output into blocks. Of
   three full-screen sketches, the workspace with a side panel was chosen.

5. (2026-10-19) A pixel-art cat in a fez greets an empty conversation, as
   Claude Code's and Codex's mascots do. Unlike round 2's mascot it is its
   own character, not a copy, and it shows only while there is nothing else
   to show ([0011](../decisions/0011-pixel-art-mascot.md)).

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
`input: () async -> AgentInput?` (`nil` ends the session). `AgentInput` is
`.message(String)`, or `.clear`, which asks the agent to drop the
conversation and its totals and to wait for the next message instead. The
events:

- `.status(StatusLine)` before each prompt ([status line](tools.md#the-status-line)),
- `.thinking` before each model call,
- `.reasoningDelta(String)` for each piece of the model's reasoning,
- `.replyDelta(String)` for each piece of the model's text as it streams in,
  then `.reply(String)` with all of it,
- `.toolCallWriting(name:)` when the model starts writing a tool call (its
  arguments still streaming; the tool runs once the reply is complete),
- `.toolStarted(name:arguments:)` before a tool runs, and
  `.toolFinished(name:arguments:output:failed:)` after it, with what the model
  sees; `failed` is set for an unknown tool or a thrown error.

### ChatSession: the state

[`ChatSession`](../../Sources/TagKit/ChatSession.swift) is a
`@MainActor @Observable` class. `handle(_:)` turns events into:

- `blocks`, one `LiveBlock` per block, each an `@Observable` object of its
  own so that a growing reply changes its block and not the list
  ([why](#keeping-frames-cheap)). `transcript` is the same as
  [`TranscriptBlock`](../../Sources/TagKit/Transcript.swift) values, for key
  handlers and tests; reading it in a view body would observe every block.
  A block's `content` is `user`, `reasoning(Reasoning)`, `reply`,
  `tools([ToolRun])` or `edit(FileEdit)`.
  Blocks can change after they appear: a reply grows with each
  `.replyDelta` (the first one sets the activity to `writing`) and `.reply`
  settles it on the full text; a reasoning block grows with each
  `.reasoningDelta` and gets its `duration` when the model moves on (text,
  a tool call, a tool run or the next prompt); tool calls between two replies share
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
suspends on a `CheckedContinuation` until `submit`, `end()` or cancellation;
what it hands the agent is an `AgentInput`: a message, or a clear.

`/clear` is the one command, alone on the line apart from whitespace. It
isn't recorded in `history`, and `take(_:)` empties `transcript` and
`expanded` — block ids start over, so a kept id would expand the wrong block —
and hands out `.clear`. The agent then keeps the system prompt but forgets
what the model was told, and resets its context, cost and date note, so the
next message is dated again. Typed while the agent is busy the command queues
like a message and takes effect at the next prompt.

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
  `scrollTo(id:)` on the selected block (the `ForEach` gives each row its
  block's id), and leaving it calls `scrollTo(edge: .bottom)`. Once the user
  scrolls away (`isPositionedByUser` and `edge != .bottom`), the footer
  offers `↓ latest`; the footer reads the position itself through a binding,
  so a scroll rebuilds the footer and not `ChatView`.
  A scroll indicator takes the rightmost column when the content overflows.
  Each block is a `BlockRow`, which reads its `LiveBlock`, fills the pane's
  width, takes clicks and hover itself (hover goes to the pane's
  `HoverState` object), and is `Equatable` (same objects, same flags), around
  `BlockView`, which draws it: user messages bold after a gold `▌`;
  replies through [`Markdown`](../../Sources/TagKit/Markdown.swift), one
  `Text` per line in a `VStack` (a blank line is a space so it keeps its row);
  `ReasoningView`, dim: `◌ thinking` and the last three lines of the
  reasoning while it streams (`.lineLimit(3)` with `.truncationMode(.head)`,
  which keeps the end of the text since Stipple 0.3.1, over only the last
  1,200 characters, `ReasoningView.tail(of:)`), then one line,
  `▸ thought · 3.1s`, that expands to all of it;
  `ToolTray`, one summary line (`▸ 3 tools · 4.2s  read_file · bash`, the `▸`
  red if one failed) that lists every call while running or when expanded,
  with the first six lines of each output; `EditCard`, a bordered diff with
  the path and `+n −m` in its top edge, the first eight lines until expanded.
  The block selected in browse mode gets a tinted background.
- `Welcome` ([Mascot.swift](../../Sources/TagKit/Mascot.swift)): what the
  pane shows instead of the scroll view while `session.blocks` is empty, at
  start and after `/clear`. The cat, `Tag Agent` in gold and
  `ask anything below · ^p commands`, centred. Terminals shorter than
  `Welcome.catMinimumHeight` (20 rows) leave out the cat. `Mascot.sprite` is
  the cat as one character per pixel with a `palette`; `Mascot.lines` draws
  it with `▀`, two pixels to a cell (the upper one as foreground, the lower
  as background; `▄` or a space where one is transparent), 18 × 9 cells. The
  README images are drawn from the same sprite
  ([0011](../decisions/0011-pixel-art-mascot.md)).
- `SessionPanel` (30 columns, hidden below 90): the model, the folder, a
  context gauge (`━`, turquoise, gold past 50%, red past 80%), tokens, cost and
  session time, the files changed and the queued messages.
- The input: a rounded box, gold while the agent waits (`ask anything`), gray
  while it works (`type ahead…`).
- `Footer`: key hints, or a warning (`press ctrl-c again to quit`), on the
  left; the spinner with the current activity and its time on the right.
- `CommandPalette` ([CommandPalette.swift](../../Sources/TagKit/CommandPalette.swift), with
  `Clipboard`): an overlay with a `SelectionList` of `PaletteCommand`s.
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

Typing `/clear` on its own line starts the conversation over: the transcript
empties and the agent forgets the context, instead of the line becoming a
message the model sees.

`ChatView.renderOptions` turns on the alternate screen and turns off Stipple's
`exitOnCtrlC`, so Ctrl-C reaches the view's `onKeyPress`. The keys the
`TextField` leaves alone are mapped by the pure `PromptKey` and `BrowseKey`
types. Tab also moves Stipple's focus, harmlessly: the input is the only
focusable view.

[Tag.swift](../../Sources/Tag/Tag.swift) wires everything up: a
`ChatSession`, an `Agent` with `output: session.handle` and
`input: session.nextMessage`, then
`Stipple.run(ChatView(...), options: ChatView.renderOptions)`.

## Choosing models

What the user asked for and the mockups:
[model picker design](../designs/model-picker.md). The providers behind it:
[models and providers](model-providers.md).

- [`ModelSelection`](../../Sources/TagKit/ModelSelection.swift) is the
  observable state. It holds the current `ActiveModel` and its effort, the
  catalogue, the connected providers and the recent models. It restores
  `Settings.lastModel`, switches and saves through `Settings.use`, stores
  pasted API keys, and runs the browser sign-in through a closure from
  [`Tag.swift`](../../Sources/Tag/Tag.swift), which retries once with the
  consent screen when ChatGPT plan usage wasn't granted.
- **Startup:** when `restoreLastModel()` fails,
  [`OnboardingView`](../../Sources/TagKit/OnboardingView.swift) runs as its
  own `Stipple.run` before the workspace: welcome, connect, pick, done.
  Ctrl-C there quits with no model.
- **The picker** (`/model`, or "Switch model" in ^p) has a search line, then
  the list, then the effort line and the key hints.
  - Typing searches. Every word must match a word prefix (3 points), a
    substring (2) or letters in order (1) of the name, the id or the
    provider and its aliases. `/` splits words.
  - With an empty search the list shows "recent" first, then every model
    grouped by provider in registry order. Providers whose catalogue failed
    show as red rows.
  - ↑↓ and PgUp/PgDn move, ←→ cycle the effort (the remembered one, else
    "medium"), ↵ uses the model, ^a connects a provider, and Esc closes.
- **`/model <provider>/<model>`** switches only on an exact match. Otherwise
  it opens the picker with the text as the search. Like `/clear`, it isn't
  sent to the model and isn't recorded in history.
- **Connecting** ([`ProviderSetup`](../../Sources/TagKit/ProviderSetup.swift)):
  API keys are masked to their last four characters and must contain no
  spaces. ChatGPT shows OpenAI's required label "Continue with ChatGPT",
  then a spinner while the browser is open; Esc cancels.
- **Plan notices:** the session panel says "Using ChatGPT plan" for Codex
  models. The first such model shows the one-time "You're using your ChatGPT
  plan" / "Got it" notice. A failed model call is a `.failure` transcript
  block: a red ✗ with the recovery (such as *Manage usage*) dim below it.
- **Why not a `TextField` for the search:** Stipple sends a key to the
  focused view first, and a `TextField` takes ←→ and Ctrl-A, which the
  picker needs. While an overlay is open, the chat input is unfocused and
  `.focusable(false)`, and
  [`ModelFlow`](../../Sources/TagKit/ModelFlow.swift) routes every key. That
  routing lives outside `ChatView` so it can be tested.
- **Frame cost:** `ChatView` reads only `ModelFlow.isOpen`, so typing in the
  picker rebuilds only the picker. Search words are prepared once per
  catalogue, rows are rebuilt only when the search or the catalogue changes,
  and only the visible window is drawn.

## Why the main actor

Stipple views and state live on the main actor, so `ChatSession.handle` is a
`@MainActor` method. The old `output` was a nonisolated synchronous closure,
and a main-actor function can't be passed where one is expected. Rather than
hop with a fire-and-forget `Task { @MainActor in … }` per event (no guarantee
the UI has the event before the loop moves on), `Agent` became `@MainActor`
too. It only awaits the model and the tools, so the UI stays live while they
run.

"Only awaits" needs care: with `NonisolatedNonsendingByDefault` (on in Tag and
the SDK), a nonisolated `async` function runs on its caller's actor. The
SDK's `chat.stream` therefore encoded the whole conversation and decoded
every chunk on the main actor, and the first key typed after sending a
message waited for the request. `OpenRouterChatModel.chunks(of:from:)` runs
the request in a `Task.detached` and hands decoded chunks to the main actor
through an `AsyncThrowingStream`; cancelling the consumer cancels it.

`AsyncParsableCommand.run()` is nonisolated, so `Tag` calls a `@MainActor`
static helper (`chat()`) that builds everything and runs the view.

## Streaming

Replies stream: the text appears as the model writes it instead of all at
once when the reply is complete, so the agent feels responsive even when a
long answer takes many seconds. Reasoning streams into its own block before
the text, and while the model writes a tool call (a long `edit_file` can
take seconds) the footer says `writing edit_file` instead of `thinking`.
The tool's arguments are not shown while they stream: the tray and the diff
card parse complete JSON, and the tool only runs once they are complete. Every delta changes one block, which
Stipple observes; Stipple's runtime batches the changes in one main-actor turn
and draws at most `RenderOptions.maxFps` (30) frames a second, so a fast model
doesn't redraw the screen per token. Checked live by timing when words of a
long reply first reached the pseudo-terminal: they arrived across many frames.

### Keeping frames cheap

Stipple lays out the whole view tree every frame, so what a frame costs
depends on how much of the tree a change touches. Before Stipple 0.3.2 and
the changes below, a frame re-wrapped every block of the transcript: a
debug-build frame took about 125 ms at 40 blocks and a second at 320, typing
lagged while a reply streamed, and the workspace dropped to about one frame a
second after a few messages. Now:

- **Stipple 0.3.2 keeps layout work across frames**: sizes, wrapped lines
  and placements stay until the views below change, and off-screen text isn't
  drawn ([Stipple's view system](https://github.com/telip007/stipple/blob/main/wiki/concepts/view-system.md#retained-layout)).
- **A delta rebuilds one row.** Each block is its own observable `LiveBlock`,
  so a delta invalidates that block's `BlockRow` and not `TranscriptPane`.
  When the pane does rebuild (a new block, expanding, hover), the other rows
  are `Equatable` and equal, and Stipple skips them.
- **Only the growing line is wrapped again.** A reply is one `Text` per line,
  and `Text` is `Equatable`, so the lines that didn't change keep their
  wrapped layout.
- **Streaming reasoning wraps its tail**, not everything the model reasoned.

- **Stipple 0.3.3 resumes wrapping text that only grew** and draws a key
  press at once instead of at the next throttled frame (30 fps would make a
  key wait up to 33 ms). `Markdown.inline` skips its regex on lines without
  markers.
- **The model call runs off the main actor** ([why](#why-the-main-actor)).

- **Stipple 0.4.0 makes a frame cost what is on screen**: lazy moves,
  off-screen rows skipped in drawing and hit testing, tree walks that skip
  subtrees, text measured from word widths with lines only for drawn text,
  and a resize that updates an observable size instead of the environment.
- **Nothing rebuilds every row.** `BlockRow` applies the row's frame, tap
  and hover itself, so the `ForEach` element is one `Equatable` view: a pane
  rebuild compares rows instead of rebuilding four modifier nodes for each.
  Rows fill the pane, so the stack's width never follows its widest row: a
  streamed line growing past the others re-measured every row at each new
  width. Scrolling doesn't rebuild `ChatView` (the footer reads the scroll
  position), so it doesn't rebuild the pane either.
- **Stipple 0.5.0's `LazyVStack` holds the transcript.** A resize lays out
  the rows in view at once and the long history above over the next frames;
  scrolled up, the first row in view stays where it is while the rows above
  settle. `TranscriptPane` is `Equatable` on the session and the selection,
  so the `ChatView` rebuild a resize causes (it reads the terminal size)
  doesn't rebuild the pane and its rows.
- **Only changed rows are written.** `renderOptions` turns on Stipple's
  incremental rendering, which rewrites each changed row from its first
  changed column: a typed key writes about 350 bytes instead of a whole
  frame, which matters most when the machine is busy.

Measured with the real view tree (debug and release builds, 80×24, 140×40
and 250×70, up to 1,500 blocks) for the worst frame of each interaction while
a reply streams. Release, 1,500 blocks: idle about 1 ms, a streamed delta
3 ms, a scroll 4 ms, expanding a block 4 ms, a resize 7–8 ms pinned to the
bottom and 8–16 ms scrolled up (24 ms once, at 751 blocks, in the frame where
the rows above settle). Debug, 1,500 blocks: at most about 26 ms for all of
them, except one 44 ms settling frame in a short session. Live, in a pseudo-terminal, typing a character every
200 ms while long replies streamed, in rounds that also resized the
terminal every 400 ms, paged the transcript every 700 ms, or ran a busy loop
on every core:

| build | plain | resizing | scrolling | busy machine |
| --- | --- | --- | --- | --- |
| release, echo p95 / max | 8 / 23 ms | 9 / 16 ms | 7 / 11 ms | 21 / 30 ms |
| debug, echo p95 / max | 16 / 29 ms | 16 / 21 ms | 15 / 19 ms | 30 / 32 ms |

Users run the optimised build (`make run`, `swift run -c release Tag`),
which is several times faster than these debug numbers.

On the busy machine, a program that only echoes the line reached 9 ms p95,
so about half of that tail is the machine. Raising the main thread's QoS
was tried and had no measurable effect here: processes started by the tool
runner stayed at the default priority.

Measured on a debug build at 242 blocks: an idle frame (the spinner) takes
4 ms instead of ~800, a frame per streamed delta 8 ms instead of 640, and a
delta of a 4,000-character paragraph 9 ms. Checked live by typing a
character every 200 ms into the pseudo-terminal while four long replies
streamed (the last one a single 700-word paragraph): typing echo stays at
10–12 ms median, 14–16 ms p95 and at most 36 ms in every reply, and the main
actor was never more than 40 ms late. The version before took 63, 95 and then
132 ms (median) and kept growing.

How to measure it, and the traps on the way:

- Search the pty output **as one buffer**: a frame arrives in pieces of about
  1 KB, and a typed run split between two pieces looked like a key that
  took hundreds of milliseconds.
- Don't rescan everything the pty sent on every poll: the scan starved the
  harness's reader thread, the pty filled up and Tag's writes blocked, which
  looked like a 1–2 s freeze.
- Don't attach `sample` during the run: attaching suspends the process.
- To tell Tag from the harness, log inside the process: the time each key
  arrives and is drawn, and a main-actor watchdog that logs late wake-ups.
- Keep the typed line shorter than the input field, or the run scrolls out
  of view and never matches.
- With incremental rendering the bytes no longer contain whole rows:
  feed them to a small terminal emulator and search the screen.
- Compare against a baseline under load: an echo-only program shows what
  any process gets from a busy machine.

## Testing

- [MascotTests.swift](../../Tests/TagKitTests/MascotTests.swift): the welcome
  shows the cat only in an empty conversation and only when tall enough, and
  the sprite's half blocks and colours.
- [BannerScreenTests.swift](../../Tests/TagKitTests/BannerScreenTests.swift)
  is not a check: with `TAG_BANNER_SCREEN` set it renders a scripted session
  into the ANSI screen the README banner is drawn from, and it is skipped
  otherwise.
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

- **Stipple focuses a node whose `@FocusState` is requested even when it
  isn't focusable.** Hiding the input under an overlay needs both
  `isInputFocused = false` and `.focusable(false)`.
- **Overlays need Stipple 0.5.1 or later.** Before it, `.background(_ color:)`
  only recoloured cells, so the session panel's text showed through the
  model picker wherever the picker's own content was blank. 0.5.1 paints
  background-coloured spaces, as Ink does.
- **Before Stipple 0.5.2 a value read only inside a `ForEach` row closure
  didn't redraw.** ↑↓ in "connect a provider" moved the highlight, but the
  list stayed put. `ProviderSetup` reads the highlight in its body, and 0.5.2
  tracks `ForEach` updates. `OnboardingRunTests` and `WorkspaceRunTests`
  drive the real views through Stipple's runtime with typed keys, which
  catches this kind of bug where `renderToString` can't.
- **A paste without an `.onPaste` handler arrives as one `KeyPress`** with
  the whole text in `characters`. Typing paths read `typedText`, which
  covers both cases.

- **Reading `session.transcript` in a view body observes every block**, so
  that view rebuilds on every delta. Views read `blocks` and the one
  `LiveBlock` they show.
- **`BlockRow.==` must compare everything its body reads but doesn't observe**
  (the flags, the session and hover objects); otherwise Stipple keeps a stale
  row.
- **Don't read the scroll position in `ChatView`'s body**: every scroll would
  rebuild the whole workspace. The footer reads it.
- **A submitted message becomes a block when the agent takes it**, not on
  `submit(_:)`: the waiting `nextMessage()` resumes later. A scripted session
  that sends events right after `submit` must wait for the block first, or the
  message lands after the reply.

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
  handler).
- **`lineLimit` kept the first lines even under head truncation** in Stipple
  0.3.0, so the reasoning preview showed the start of the reasoning, not the
  latest lines. Fixed upstream in 0.3.1, as in SwiftUI; `Package.swift`
  requires it.
- **SwiftLint's `type_body_length` (200 lines)** applies to `ChatView` and to
  test suites. Helpers live in an `extension ChatView` in the same file
  (`fileprivate`, so they still reach the `private` state), and the key-map
  tests are their own suite.
