# Wiki log

Append-only. Format: see [SCHEMA.md](SCHEMA.md#log-format).

## [2026-10-17] ingest | Don't waste your back pressure
Captured Moss's essay (via ghuntley.com/pressure) as the rationale for the tooling setup.

## [2026-10-17] ingest | LLM wiki pattern
Captured Karpathy's idea file; instantiated as this wiki (schema, index, log, raw/sources/concepts/decisions).

## [2026-10-17] decision | Project foundations
Recorded decisions 0001–0004: hand-written agent code, maximum backpressure, SDK as submodule, LLM-maintained wiki.

## [2026-10-17] update | Backpressure tooling and agent workflow
Documented the strict compiler settings, swift-format/SwiftLint configs, coverage gate, git hooks, Claude Code hooks and skills.

## [2026-10-17] update | SDK published, submodule, CI, rename
The SDK was published as its own public repository and added here as a git submodule. Added CI (macOS, `make check`), README, AGENTS.md/CLAUDE.md; the project is now called Tag Agent. Wiki lint now also rejects home paths and emails.

## [2026-10-17] update | SDK 0.1.0
Submodule moved to the swift-openrouter 0.1.0 release (Linux fix, release tooling). The SDK's pre-push hook now also runs its Linux tests in Docker.

## [2026-10-17] decision | Tag and TagKit targets
Split Package.swift into a thin `Tag` executable and a `TagKit` library that owns the OpenRouter dependency (decision 0005).

## [2026-10-17] update | SwiftLint in Xcode
Added the SwiftLintPlugins build tool plugin (pinned to 0.65.1) to both targets, so lint runs on every build and shows inline in Xcode. Documented Xcode's built-in swift-format and the whitespace settings.

## [2026-10-17] decision | Agents build the harness
Decision 0006 supersedes 0001: after the hand-written first loop, agents write `Sources/` code too. Updated AGENTS.md, CLAUDE.md and README.md.

## [2026-10-18] update | Tools: read_file, list_files, edit_file
Finished the "How to build an agent" port: the loop now runs tool calls and feeds results back, with the tutorial's three file tools. Added the `TagKitTests` target (loop with a scripted model, tools in a temp directory), so tests and the coverage gate now run.

## [2026-10-18] update | Tools: bash and code_search
Added the workshop's `bash` and `code_search` tools, running processes through swift-subprocess 1.0. ripgrep is now installed by `make bootstrap` and CI; the real-rg test is skipped without it.

## [2026-10-18] update | Published on GitHub
Tag Agent is now public at github.com/telip007/tag-agent under Apache 2.0, with the same community files as the SDK (CONTRIBUTING, SECURITY, CODE_OF_CONDUCT, issue/PR templates, Dependabot). `.swiftpm/` is ignored: Xcode schemes store environment variables such as API keys there.

## [2026-10-18] decision | Conventional Commits
Decision 0007: the SDK's Conventional Commits format and checker, enforced by a `commit-msg` hook and a CI PR-title job. release-please is deferred until something is releasable.

## [2026-10-18] update | README banner
Added `.github/assets/banner.png`: a text-free background generated with Codex (Ottoman girih and Iznik motifs with circuit traces) plus exact text and a sample session drawn by `.github/assets/compose-banner.swift`, as in the SDK.

## [2026-10-18] update | swift-tools-version 6.2
First CI run failed: `Package.swift` declared tools 6.4, CI has Swift 6.3. Lowered to 6.2 (the documented minimum, same as the SDK).

## [2026-10-18] update | Status line
Added `StatusLine` (`Sources/TagKit/StatusLine.swift`) and gave `ChatModel` a
`modelDescription()` method. Before each prompt Tag prints the working folder,
the model's catalogue display name, the context use against its window and the
session cost. Documented the loop change and the new compiler traps in
[tools](concepts/tools.md).

## [2026-10-18] update | Terminal UI on Stipple
The chat UI moved from print/readLine with raw ANSI escapes to a Stipple view (decision 0008). `Agent` is now `@MainActor` and emits `AgentEvent`s; `ChatSession` holds the UI state and `ChatView` renders it, both in TagKit so they are testable. Piped stdin input no longer works. See [terminal UI](concepts/terminal-ui.md).

## [2026-10-18] update | Terminal UI design pass
Restyled the chat for "a simple look that reveals hidden aha moments; retro but state of the art": amber accent, banner, `›` prompt, tool summaries and durations, turn summaries, braille spinner, a status bar with a context meter that narrows with the terminal. Added type-ahead, ↑/↓ history, Ctrl-C/Ctrl-D handling, and split tool events into started/finished. Two Stipple fixes (colour-depth downsampling, Ctrl-D in an empty TextField) are being made upstream.

## [2026-10-18] update | Stipple 0.1.1

Three Stipple bugs found while building the terminal UI were fixed upstream and
released as Stipple 0.1.1: colour-depth detection with RGB downsampling, Ctrl-D
reaching ancestors on an empty `TextField`, and the caret moving to the end
after outside text changes. `Package.swift` now requires 0.1.1; the gotchas in
[terminal UI](concepts/terminal-ui.md) say which version fixed what. The model's
catalogue name is shown without its author prefix (`ModelDescription.displayName`).

## [2026-10-18] update | Terminal UI redesign

The first look was flat and cramped next to current agent CLIs. Redesigned
after Claude Code and Pi: a header with a pixel-art mascot (a turquoise creature in a turban with a
gold jewel and cobalt plume; a fez variant is drawn too), user
messages on a tinted band, replies indented to the message text, the input
between two rules, and a two-sided status bar. Dropped the ` TAG ` badge, the
`▰▱` meter and the summary line for turns without tools. Replies now render a
light Markdown subset (`Markdown.swift`). Palette moved from amber phosphor to
manuscript gold and İznik turquoise. See [terminal UI](concepts/terminal-ui.md).

## [2026-10-18] update | Mascot

Replaced the star logo with a mascot drawn by `PixelArt` (half blocks, two
colours per cell): `Mascot.turban` by default, `Mascot.fez` as the alternative.
Why a character and not a star, and what was dropped, is in
[terminal UI](concepts/terminal-ui.md#the-mascot).

## [2026-10-18] update | Full-screen workspace

The second redesign was rejected as a copy of Claude Code, and so was its
mascot. Rebuilt as a full-screen workspace after researching 2026 agent CLIs:
the conversation pane, a session panel (model, context gauge, cost, time,
files changed), a boxed input and a footer of key hints. Transcript blocks
replace lines: tool trays that grow and collapse, diff cards from `edit_file`
calls. Browse mode (Esc), a command palette (Ctrl-P), a panel toggle (Tab) and
OSC 52 copy. Tool output now travels in `.toolFinished`. Removed the mascot
and `PixelArt`. The design history is in
[terminal UI](concepts/terminal-ui.md#design).

