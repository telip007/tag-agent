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
