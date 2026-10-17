---
title: Backpressure setup
summary: Every automated check in this repo, where it runs, and the traps we hit wiring it up.
updated: 2026-10-17
---

# Backpressure setup

Why: [0002 Maximum backpressure](../decisions/0002-maximum-backpressure.md),
based on [Don't waste your back pressure](../sources/dont-waste-your-backpressure.md).
The same setup is mirrored in the swift-openrouter SDK (see
[OpenRouter SDK](openrouter-sdk.md)).

## The checks

| Check | Config | Runs in |
| --- | --- | --- |
| Swift 6 language mode, complete concurrency checking | default for tools-version 6.x | every build |
| Upcoming features `ExistentialAny`, `InternalImportsByDefault`, `MemberImportVisibility`, `NonisolatedNonsendingByDefault`, `InferIsolatedConformances`, plus `strictMemorySafety()` | `strictSettings` in [Package.swift](../../Package.swift) | every build |
| All warnings are errors | `.treatAllWarnings(as: .error)` | every build |
| Formatting (4 spaces, 120 cols, doc comments on public API, no force unwraps/try) | [.swift-format](../../.swift-format) (`swift format`, bundled with the toolchain) | `make lint`, pre-commit, PostToolUse hook, CI |
| Semantic lint (~60 opt-in rules, small functions/types/files) | [.swiftlint.yml](../../.swiftlint.yml), `--strict` | `make lint`, pre-commit, PostToolUse hook, CI |
| Tests + line-coverage gate (80 %, generated code excluded) | [Scripts/check-coverage.py](../../Scripts/check-coverage.py), `MIN_COVERAGE` in [Makefile](../../Makefile) | `make check`, pre-push, CI |
| Wiki structure and privacy (no home paths or emails) | [Scripts/wiki-lint.py](../../Scripts/wiki-lint.py) | `make lint`, pre-commit, CI |
| Everything above on a clean machine | [.github/workflows/ci.yml](../../.github/workflows/ci.yml) (`macos-26`, submodules checked out) | CI on push and PR |

`make check` = wiki lint + format lint + SwiftLint + build + tests + coverage.
Git hooks live in [.githooks](../../.githooks/pre-commit) (pre-commit: lint;
pre-push: full check). They're activated by `make bootstrap`, and
automatically by the Claude Code SessionStart hook (see
[Agent workflow](agent-workflow.md)).

Tag Agent has no `Tests/` yet. The Makefile skips tests and coverage until the
directory exists, then enforces both automatically. When adding tests,
consider splitting a `TagCore` library target out of the executable so it can
be imported by tests.

## Gotchas

- **swift-format vs SwiftLint on `case let`.** swift-format's
  `UseLetInEveryBoundCaseVariable` wants `case .x(let a)`, while SwiftLint's
  `pattern_matching_keywords` wants `case let .x(a)`. We disabled the SwiftLint rule:
  swift-format owns layout, SwiftLint owns semantics. Other layout rules that
  SwiftLint would fight over are disabled in `.swiftlint.yml` for the same
  reason.
- **`multilineTrailingCommaBehavior: alwaysUsed` is buggy** in the
  toolchain's swift-format: it produces `],)` after wrapped arguments and then
  flags its own output. We use `keptAsWritten`.
- **`NonisolatedNonsendingByDefault` changes closure types.** Conforming to
  protocols compiled without it (e.g. OpenAPIRuntime's `ClientMiddleware`)
  needs explicit `@concurrent @Sendable` on closure parameters.
- **`discouraged_none_name` found a real bug.** A static member called
  `none` on a type used as an optional (`toolChoice: .none`) resolves to
  `Optional.none`, i.e. `nil`. Never name members `none`.
- **`treatAllWarnings` only applies to targets that opt in.** Generated code
  targets deliberately don't (deprecation warnings from the upstream spec).
- Timing-based compiler flags (`-warn-long-expression-type-checking`) were
  rejected. They're nondeterministic across machines, which makes for bad
  backpressure.
