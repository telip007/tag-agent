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
