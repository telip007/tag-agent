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
Added `.github/assets/banner.png`: a text-free background generated with Codex (geometric ornament with circuit traces) plus exact text and a sample session drawn by `.github/assets/compose-banner.swift`, as in the SDK.

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
after Claude Code and Pi: a header with a pixel-art mascot (a turquoise creature with a gold jewel and
cobalt plume; a second variant is drawn too), user
messages on a tinted band, replies indented to the message text, the input
between two rules, and a two-sided status bar. Dropped the ` TAG ` badge, the
`▰▱` meter and the summary line for turns without tools. Replies now render a
light Markdown subset (`Markdown.swift`). Palette moved from amber phosphor to
gold and turquoise. See [terminal UI](concepts/terminal-ui.md).

## [2026-10-18] update | Mascot

Replaced the star logo with a mascot drawn by `PixelArt` (half blocks, two
colours per cell): two variants, one the default.
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

## [2026-10-18] update | Scrolling and mouse

Stipple 0.2.0 added `ScrollView`, `ScrollPosition`, mouse-wheel scrolling and
`.onTapGesture`, built for this workspace. The transcript scrolls and follows
the newest block, browse mode scrolls the selection into view, Page Up/Down
work while typing, and with mouse reporting on, the wheel scrolls, clicks
expand blocks, and footer hints and palette rows are clickable. A `↓ latest`
hint appears after scrolling away. See [terminal UI](concepts/terminal-ui.md).

## [2026-10-18] update | Hover, and short conversations start at the top

Stipple 0.3.0: clicking the input focuses it, hovering a tool tray or diff
tints it and hovering a footer hint lights it up. At the maintainer's request a
short conversation now starts at the top of the pane; the scroll view is
anchored to the bottom only for its initial offset and for growth.

## [2026-10-18] ingest | System prompt and caching sources
Captured mini-swe-agent, OpenAI's prompt engineering best practices, Tetrate's system prompts guide, pi's system prompt builder and OpenRouter's prompt caching guide. mini-swe-agent's page lists 18 things Tag can borrow.

## [2026-10-18] query | System prompt and prompt caching
New pages [system prompt](concepts/system-prompt.md) (best practices, draft, runtime environment, open questions) and [prompt caching](concepts/prompt-caching.md) (current state, gaps, steps). Tag has neither a system prompt nor explicit caching yet; no decision recorded.

## [2026-10-18] update | System prompt
Tag now sends a system prompt (decision 0009): `SystemPrompt.render` builds it from sections, each `ToolDefinition` adds a `summary` and `guidelines`, `SessionEnvironment.probe` supplies folder, OS, shell, git and `AGENTS.md` once at startup, and `UserMessageDater` puts the date on user messages instead. `Agent` takes a `SessionEnvironment` instead of a working directory. See [system prompt](concepts/system-prompt.md).

## [2026-10-18] update | Hook tests and GIT_DIR
The pre-push hook failed a probe test that `make check` passed: hook-run tests inherit `GIT_DIR`, so a command in a temporary folder answers for this repository. The test no longer checks the repository field; gotcha in [backpressure setup](concepts/backpressure-setup.md).

## [2026-10-18] ingest | Karpathy guidelines
Captured the Karpathy guidelines skill and took three of its ideas into the system prompt's rules: write the simplest code with nothing speculative, mention unrelated problems instead of fixing them and remove only your own leftovers, and name the readings of an ambiguous request instead of picking one. The style, persona check, plan template and general "stop and ask" were left out; see [Karpathy guidelines](sources/karpathy-guidelines.md).

## [2026-10-18] update | Evaluation loop plan
New page [evaluation loop](concepts/evaluation-loop.md): model tiers, what Tag needs first (headless mode, saved trajectories), task set, grading, the change-one-thing loop, and open questions for a working session. Nothing built or decided yet.

## [2026-10-18] update | Reply streaming
Replies stream into the workspace: `ChatModel.reply(to:tools:onText:)` streams through the SDK's `chat.stream`, the agent emits `.replyDelta` per piece and `.reply` at the end, and `ChatSession` grows one reply block. The SDK's stream accumulator now keeps reasoning on the message.

## [2026-10-18] update | Streamed reasoning and tool-call names
`ChatModel` streams `ReplyDelta`s (text, reasoning, tool-call names). Reasoning gets its own transcript block (`◌ thinking` with its latest lines, then `▸ thought · 3.1s`, expandable), and the footer shows `writing <tool>` while a tool call streams. Needed Stipple 0.3.1, where head truncation keeps the last lines of a line-limited text.

## [2026-10-18] update | `/clear` restarts the conversation
Typing `/clear` at the prompt starts over: `ChatSession` empties `transcript` and `expanded` (block ids restart) and the agent drops what the model was told, its context, cost and date note, keeping the system prompt. The agent's input closure now returns an `AgentInput` (`.message` or `.clear`) instead of a `String`, so `Agent.getUserMessage` became `Agent.input`; `ChatSession.take(_:)` absorbs the old `send(_:)`. Queued while the agent is busy, the command takes effect at the next prompt. See [terminal UI](concepts/terminal-ui.md#chatsession-the-state) and [tools](concepts/tools.md#the-loop).

## [2026-10-18] update | Street cat branding
Light rebrand ([0010](decisions/0010-street-cat-branding.md)): new `logo.png` and banner background generated with Codex (a tabby street cat in a fez over lamp-lit rooftops), `compose-banner.swift` places the logo beside the title, README gets a short Mascot section. Public wiki wording about the old ornament and palette was made neutral.

## [2026-10-19] update | Smooth workspace: retained layout and per-block updates
Typing lagged while replies streamed and the workspace slowed to about a frame a second after a few messages, because every frame re-laid out and re-wrapped the whole transcript. Stipple 0.3.2 keeps layout work across frames; `ChatSession` holds each block as an observable `LiveBlock`, rows are `Equatable` `BlockRow`s, replies are one `Text` per line and streaming reasoning wraps only its tail. Debug-build frames at 242 blocks: 4 ms idle, 8 ms per delta (from ~800 and 640); live typing echo stays at ~13 ms. Browsing after a `/clear` emptied the transcript no longer indexes past it. The command palette and clipboard moved to `CommandPalette.swift`. See [terminal UI](concepts/terminal-ui.md#keeping-frames-cheap).

## [2026-10-19] update | Typing stays smooth under any reply
Stipple 0.3.3: text that only grew resumes wrapping, and key presses draw at once. `OpenRouterChatModel` runs the request and chunk decoding in a detached task: under `NonisolatedNonsendingByDefault` they ran on the main actor and held up the first key after sending. `Markdown.inline` skips its regex on lines without markers. Live: typing echo at 10–12 ms median and at most 36 ms through four long replies, one of them a single 700-word paragraph; the harness pitfalls that faked stalls are on the [terminal UI](concepts/terminal-ui.md#keeping-frames-cheap) page.

## [2026-10-19] update | Smooth at any length, size and load
Stipple 0.4.0 (frames cost what is on screen). `BlockRow` applies the row's frame, tap and hover itself and fills the pane, hover lives in a `HoverState` object, the footer reads the scroll position so scrolling doesn't rebuild `ChatView`, and incremental rendering writes only changed rows. Measured across sizes, 1,500 blocks, debug and release, and live while resizing, scrolling and under full CPU load; numbers and method in [terminal UI](concepts/terminal-ui.md#keeping-frames-cheap).

## [2026-10-19] update | `make run` runs the optimised build
The README and `make run` start Tag with `swift run -c release Tag`: the debug build draws several times slower, which shows when resizing a long session. See [terminal UI](concepts/terminal-ui.md#keeping-frames-cheap).

## [2026-10-19] update | Lazy transcript
Stipple 0.5.0: the transcript is a `LazyVStack`, so resizing a long session lays out the rows in view first, pinned or scrolled up (the first row in view stays put). `TranscriptPane` is `Equatable`, so a resize no longer rebuilds it. Release, 1,500 blocks: every interaction at most about 8 ms except resizing while scrolled up (8–24 ms); debug at most about 26 ms. See [terminal UI](concepts/terminal-ui.md#keeping-frames-cheap).

## [2026-10-19] decision | Pixel-art mascot
[0011](decisions/0011-pixel-art-mascot.md): the street cat in a fez is now an 18 × 17 pixel sprite in `Mascot.swift`. `Welcome` draws it with half blocks in an empty conversation (start and after `/clear`), with the name and where to start. `render-assets.swift` replaces `compose-banner.swift` and draws `logo.png` and `banner.png` from the sprite and a real rendered screen (`banner-screen.ansi`, from `BannerScreenTests`), so the banner shows the current workspace instead of the old REPL. The README documents `/clear`, the palette, the default model and `AGENTS.md`. See [terminal UI](concepts/terminal-ui.md#chatview-the-workspace).

## [2026-10-19] decision | Model providers and user-chosen models
[0012](decisions/0012-model-providers.md): a new `ModelKit` module with neutral messages, one adapter per wire format (Chat Completions, Responses, Anthropic Messages, Gemini, OpenRouter SDK), providers for OpenRouter, ChatGPT plans (official Sign in with ChatGPT) and OpenCode Go, and `0600` credential and settings files. The agent reads the active model before every call and reports failed calls instead of ending. See [models and providers](concepts/model-providers.md).

## [2026-10-19] update | Designs live in the wiki
New `designs/` layer for brainstorms, specs, mockups and plans, including those from skills that default to `docs/superpowers/`; the model picker brainstorm moved there as [model picker design](designs/model-picker.md). `.superpowers/` is ignored.

## [2026-10-19] update | Coverage across test bundles
`make coverage` exports the merged profile against every `*Tests.xctest`: with `ModelKitTests` added, SwiftPM's codecov JSON covered only one bundle. See [backpressure setup](concepts/backpressure-setup.md#gotchas).

## [2026-10-19] update | Choosing models in the UI
Onboarding on the first start, the search-first `/model` picker, `/model <provider>/<model>`, connecting providers (masked keys, "Continue with ChatGPT"), the ChatGPT plan notices and a `.failure` transcript block. The keys, design choices and Stipple focus gotchas are on [terminal UI](concepts/terminal-ui.md#choosing-models). Tried live in a pseudo-terminal against OpenRouter: onboarding, the picker, a reply, the restored model and effort, and the quick switch.

## [2026-10-19] update | Stipple 0.5.1: opaque overlays
The model picker over the workspace let the session panel show through its blank cells. Fixed in Stipple 0.5.1 (`.background(_ color:)` paints spaces, as Ink does), and Tag now requires it. `/model x/y` no longer leaves the input unfocused, and a search that spells a whole model name ranks it first. Tried live: the quick switch keeps the conversation (the new model recalled a word from before the switch).

## [2026-10-19] update | Live probes of the Go and ChatGPT endpoints
Without credentials: OpenCode Go demands `x-opencode-session` (400 otherwise) and answers 401 without a key; OpenAI's authorize page sits behind a browser check. Gotchas on [models and providers](concepts/model-providers.md#gotchas). A real ChatGPT sign-in and Go requests with a key still need the maintainer.

## [2026-10-19] update | Live adapter tests through OpenRouter
`LiveAdapterTests` (opt-in with `TAG_LIVE_TESTS=1`) ran a real tool-call round trip through the Chat Completions, Responses and Anthropic Messages adapters on OpenRouter; all pass. They found that gateways end Anthropic streams with `data: [DONE]`, which the Anthropic and Gemini decoders now ignore. See [models and providers](concepts/model-providers.md#gotchas).

## [2026-10-19] update | Arrows in "connect a provider"
↑↓ moved the highlight but the list didn't redraw: the row closure of a `ForEach` read it, and Stipple didn't track reads there (fixed in Stipple 0.5.2). `ProviderSetup` reads the highlight in its body, and `OnboardingRunTests` types the keys through the runtime. See [terminal UI](concepts/terminal-ui.md#gotchas).

## [2026-10-19] update | Credentials across processes, and kept from the tools
Credential and settings writes hold a cross-process `flock`, and a ChatGPT refresh holds its own lock and re-reads the account, so two Tag sessions no longer spend the same rotating refresh token (which signs the user out). The file tools, `code_search` and `bash` refuse Tag's config directory. The Keychain was considered and left out ([0012](decisions/0012-model-providers.md)). See [models and providers](concepts/model-providers.md#credentials-and-settings).

## [2026-10-19] update | OpenCode Go live; ChatGPT Business blocked
The maintainer used OpenCode Go live. The ChatGPT sign-in failed on a Business workspace with `3p_delegated_access_policy_denied`: plan usage in third-party apps is for personal Plus and Pro plans, with no admin setting found. Whether to offer the Codex CLI's undocumented route is open. See [models and providers](concepts/model-providers.md#gotchas).

## [2026-10-19] update | One streaming helper
The Responses adapter now streams through `WireStream` with a `ResponsesDecoder`, like the other formats, instead of its own detached-task stream. `WireDecoder` gained an `error(status:body:provider:)` hook so Responses keeps its ChatGPT plan error codes. See [models and providers](concepts/model-providers.md#gotchas).

## [2026-10-19] update | SendableMetatype warnings slip through
`WireDecoder` now refines `SendableMetatype`: capturing a decoder's type in `WireStream`'s detached task warned, and those warnings didn't fail the build. Noted on [backpressure setup](concepts/backpressure-setup.md#gotchas).

## [2026-10-19] update | Codex CLI route written up
New design page [Codex CLI route for ChatGPT plans](designs/codex-cli-route.md): how the Codex CLI's sign-in and private backend work (from OpenAI's open-source Codex CLI), why it gets past the Business refusal, its risks and three options. Not built; the decision is open.

## [2026-10-19] update | Keep the model selection Foundation import internal
Fixed the Swift 6.3 CI build: Foundation is only used by an internal error,
so ModelSelection uses a plain import. Recorded the toolchain difference
and retained every existing lint, warning and coverage gate.

## [2026-10-19] update | Share lock-test events through a Sendable reference
After the import fix, CI reached test compilation and Swift 6.3 rejected
a nested task's direct capture of a noncopyable Mutex. A checked Sendable
reference now owns the mutex; the ordering assertion and locking stay intact.

## [2026-10-19] update | ChatGPT integration review against the cookbook
Source review confirmed the core OAuth and public API route, with gaps in JWKS signature verification, separate account registrations, tool encoding and identity-only consent handling. Business policy denial remains an account-specific eligibility question, with no documented admin override found. See [review findings](concepts/model-providers.md#sign-in-with-chatgpt-review-2026-10-19). Application code was not changed.

## [2026-10-20] update | Prompt caching across providers
Added OpenRouter opt-in boundaries, retained Anthropic previous-turn boundaries, and normalized optional cache reads/writes for every adapter. The status panel shows latest-request cache metrics; default retention and stable session routing are preserved. See [prompt caching](concepts/prompt-caching.md) and [0013](decisions/0013-prompt-caching.md).

## [2026-10-20] update | Prompt caching validation
`TAG_LIVE_TESTS=0 make check` passed: 304 tests and 91.5% line coverage at the unchanged 80% gate. Read-only review caught a missing router opt-in; the regression failed before its fix and the final full checks passed. Live cache hits and savings remain unmeasured. See [validation](designs/prompt-caching.md#verified-result).

## [2026-10-20] update | Keep cache metrics current during tool loops
Integrated main's shared Responses stream and fixed a review finding: metrics now refresh before inference and after every reply, without closing the tool tray or resetting activity. Regression tests cover missing/zero/changed counters and model switches, plus tray continuity.

## [2026-10-20] update | Prompt caching documentation audit
Documented cache metrics in the README, added ModelKit to the contributor module map, and corrected the loop page's outdated claim that explicit caching is not implemented. Clarified that cache metrics describe the latest completed reply and persist during failed or in-flight requests. Existing validation results remain historical; final integration checks are recorded separately.

## [2026-10-20] update | Prompt research and next-action benchmark
Added a source-backed staged experiment, six candidate policies and a native-tool decision screen with synthetic development/holdout fixtures. Production prompt unchanged; full coding trajectories remain required.

## [2026-10-20] update | First complete prompt development screen
Saved 144 responses across six policies and two model aliases, with zero infrastructure errors and 197,346 reported tokens. Raw-response audit limits the screen to calibration; full coding trajectories, repeats and held-out model-tier evidence remain open.

## [2026-10-20] update | Native prompt trajectories and empty reasoning replay
Built an opt-in bridge over the actual Agent, adapters and tools, validated ten development and six reserved confirmation oracles, and retained an interrupted native comparison. A live reconstructed request exposed missing empty interleaved reasoning; the regression failed before a scoped encoder repair and all eight adapter tests passed.

## [2026-10-20] update | Replay repair verified through native coding runs
Full make check passed at 91.5% coverage; all four repaired native smoke trajectories passed, including both previously interrupted task/model combinations. The new development comparison uses a fresh manifest; interrupted results remain separate and do not rank prompts.

## [2026-10-20] update | Complete native prompt comparison and cache-aware analysis
Recorded all 72 development trajectories with 70 reviewed successes, two retained transport failures and one explicit punctuation-rubric correction. Added cache/input/output separation, dated allowance-rate estimates, a frozen 98-word proposal and a pre-confirmation selection protocol. Gemini cap preservation tests failed before adding research-only support and then passed.

## [2026-10-20] update | Gemini native smoke and hybrid budget failure
Gemini passed a real native coding smoke with six calls and external checks. The 98-word hybrid development run retained a GLM output-budget failure; the verified terminal process resumes only unrun cells under the same frozen manifest. Repository checks and 23 Python tests passed; finalist confirmation remains unopened.

## [2026-10-20] update | Native prompt family analysis integrity

Added a cross-run report with duplicate-sample/control/task/policy checks and
explicit successful-pair resource conditioning. Audited an under-specified
float requirement in the config fixture: preserve the raw test failure,
exclude that task uniformly from primary selection and retain all-task
sensitivity. Finalists and confirmation remain open.

## [2026-10-20] update | Complete native prompt exploration and lean scaffold

Completed all 192 policy exploration cells. Preserved subject budget failures
and the under-specified float failure, with uniform primary-task exclusion.
Shortlisted baseline/compact/evidence/minimal for further evaluation. Added a
research-only lean scaffold; red-then-green tests preserve API tool schemas
through the actual Agent and retain rules/environment/project instructions.
No production prompt replacement or final recommendation yet.

## [2026-10-20] update | Repeat-aware prompt analysis and transfer reserve

Added task-clustered/equal-model exploratory intervals and complete-usage
cost-per-success metrics that include failed attempts. Reserved three
externally checked multi-file tasks for post-freeze transfer; no subject
requests or tuning on that reserve. Retained scaffold transport failures
and resumed only missing cells after verifying terminal state.

## [2026-10-20] update | Complete scaffold study and interleaved prompt repeats

Finished 88/88 scaffold cells, with 85 operational successes and all 72 saved
coding states externally passing. Retained network/budget failures. Validated
joint/fixed-template native treatment smokes and 34 Python checks. Started
352 interleaved new samples to complete the predeclared 528-trajectory
selected-template matrix. Reserved confirmation and transfer remain unused.

## [2026-10-20] update | Frozen context-position stress check

Reserved a bounded 18-condition post-freeze context-position check for the
remaining paper-derived hypothesis. Identical task/archive blocks are reordered
on one reserved multi-file task; this is not an independent task set. Three
renderer tests pass; active native controls remain untouched. Audited the first
repeat generation-cap failure without retry or regrading.

## [2026-10-20] update | Prompt evidence audit and literature scope

Verified the active repeat harness against all 72 frozen runtime source hashes
and the compiled bundle; reserved functional/context definitions remain fixed
and unsent. Added an explicit incomplete completion audit. Clarified that GEPA's
instance-wise Pareto selection differs from this lab's manually designed
quality/resource comparison; no MIPRO/GEPA/Self-Refine optimizer is implemented.
Audited further retained generation-cap outcomes without regrading or retry.

## [2026-10-20] update | Exact native prompt-template catalogue

Exported twelve tested templates with hashes and explicit dynamic fields;
verified roundtrips against all 280 completed exploration prompts and observed
repeat prompts. Clarified the minimal policy's whitespace word count without
changing experimental text or outcomes. Winner selection remains pending.

## [2026-10-20] update | Prompt reporting review and incomplete usage

Read-only review found no Critical or Important issue and one Minor incomplete-usage
reporting inconsistency. A failing regression now passes; all 38 Python checks pass.
Refreshed derived reports without changing raw outcomes or the pinned live runtime.

## [2026-10-20] update | Complete prompt repeats and development choice

Completed and audited all 352 fresh repeats and the exact 528-cell selection.
Prepared compact/standard for confirmation with uncertainty and tradeoffs retained.
Connected the frozen context treatment after process exit; all 40 Python tests pass.

## [2026-10-20] update | Frozen prompt recommendation and reserved confirmation

Full repository checks passed: 318 Swift tests and 91.5% coverage at unchanged gate.
Froze exact compact/standard assets and decision evidence before reserved requests.
Started 108 held-out confirmation cells; transfer and context checks remain pending.

## [2026-10-20] update | Reserved bool-interpretation caveat

Audited the first reserved baseline failure: bool acceptance versus an implicit
integer-type oracle. Retain primary raw grades; disclose a uniform whole-task
sensitivity after this outcome, without prompt tuning, fixture edits or retries.

## [2026-10-20] update | Reserved comparison report integrity

Added a freeze-bound report that preserves all-task primary grades and the separate
whole-task sensitivity, rejects missing runtime bindings, and flags incomplete or
unaudited evidence. All 42 Python tests pass; read-only review found no major issue.

## [2026-10-20] update | Genuine reserved interval-boundary failure

Reproduced a recommendation failure at the explicitly open window boundary.
Retained its original grade and clarified that whole-task ambiguity sensitivity
also drops genuine failures, so it cannot replace the all-task primary score.

## [2026-10-20] update | Complete reserved confirmation and start transfer

Verified 108/108 cells, eight failure audits, 74 frozen sources and 107 recorded
prompt texts. Compact's pooled 51/54 versus baseline 49/54 retains a GLM regression
and uncertain efficiency. Started the unchanged 54-cell multi-file transfer.

## [2026-10-20] update | Early transfer failure audit

Reproduced a baseline quoted-CSV parsing error and retained output-cap failures
under both prompts. All grades remain unchanged; transfer collection continues
without prompt edits or failed-cell retries.

## [2026-10-20] update | Transfer malformed-argument stop and bounded continuation

Traced recorded invalid JSON tool arguments through tool validation and upstream
history rejection. Kept the failed cell and frozen runtime; after verified terminal
state, the same manifest continues only 37 missing cells with prefix integrity checked.

## [2026-10-20] update | Independent CSV transfer grading review
A read-only review reproduced quoted-field failures for both prompt arms and the passing frozen reference. Primary grades remain unchanged; CSV dialect and fail-fast oracle limits are recorded in the research design and hash-bound review artifact.

## [2026-10-20] update | Ordinary reserved prompt validation complete
Verified54/54transfer cells, all26transfer failures and unchanged retained prefix; combined162/162 with34audited failures. Operational scores tie64/81, saved code67/81baseline versus65/81compact; paired efficiency gain unconfirmed. The18contextconditions and final choice/checks remain open.

## [2026-10-20] update | Independent ordinary reserved report review
Reviewer reproduced totals, intervals, failure hashes, retained prefix and runtime/template bindings with no Important or Critical findings. The two new report columns now say operational success instead of completed; scores and raw data are unchanged. Context and final selection remain open.

## [2026-10-20] update | First frozen context position complete
Beginning position completed6/6conditions: baseline3/3compact2/3operational, all6savedcodepasses. ThecompactGemini deadline remains an audited failure with unknown usage;75sourcearchives and5capturedtemplates match. Middle position is live; final choice/checks remain open.

## [2026-10-20] update | Complete measurements and retain measured baseline
All 18 context conditions completed with five audited failures; only unrun end-position cells continued after verified terminal state, preserving the original prefix. Final template retains baseline/standard, with no confirmed compact replacement advantage; reports preserve the original freeze and disclose contextual tradeoffs. Raw traces remain local and Git-ignored; final checks and closing review remain open.

## [2026-10-20] update | Final prompt verification and read-only review
Required check passed with 318 Swift tests and 91.5% coverage at the unchanged 80% gate; all 42 offline tests and exact frozen report reproduction passed. Closing review found no Important or Critical issue and supported baseline retention; stale README wording was corrected. Local privacy checks preserve immutable raw evidence outside Git.

## [2026-10-20] decision | Bounded native prompt research
Recorded the opt-in research bridge, frozen evidence, failure preservation and justified baseline retention in decision 0014. A complete run-qualified index now binds all 58 raw failures across 812 main trajectories; independent review confirmed coverage and unchanged scores.
