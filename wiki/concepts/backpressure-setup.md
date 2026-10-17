---
title: Backpressure setup
summary: Every automated check in this repo, where it runs, and the traps we hit wiring it up.
updated: 2026-10-18
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
| Semantic lint (~60 opt-in rules, small functions/types/files) | [.swiftlint.yml](../../.swiftlint.yml), `--strict` | every build (SwiftLintPlugins build tool plugin, inline in Xcode), `make lint`, pre-commit, PostToolUse hook, CI |
| Tests + line-coverage gate (80 %, generated code excluded) | [Scripts/check-coverage.py](../../Scripts/check-coverage.py), `MIN_COVERAGE` in [Makefile](../../Makefile) | `make check`, pre-push, CI |
| Wiki structure and privacy (no home paths or emails) | [Scripts/wiki-lint.py](../../Scripts/wiki-lint.py) | `make lint`, pre-commit, CI |
| Conventional Commits headers ([0007](../decisions/0007-conventional-commits.md)) | [Scripts/check-commit-message.py](../../Scripts/check-commit-message.py) | `commit-msg` hook, CI (PR title) |
| Everything above on a clean machine | [.github/workflows/ci.yml](../../.github/workflows/ci.yml) (`macos-26`, submodules checked out) | CI on push and PR |

`make check` = wiki lint + format lint + SwiftLint + build + tests + coverage.
Git hooks live in [.githooks](../../.githooks/pre-commit) (pre-commit: lint;
pre-push: full check). They're activated by `make bootstrap`, and
automatically by the Claude Code SessionStart hook (see
[Agent workflow](agent-workflow.md)).

Tests live in `Tests/TagKitTests` (Swift Testing) and import the `TagKit`
library target, not the executable (see
[0005](../decisions/0005-tag-and-tagkit-targets.md)). The Makefile only runs
tests and the coverage gate when `Tests/` exists. The test target gets the same
strict settings and lint plugin as the sources.

## Gotchas

- **`swift-tools-version` must not exceed CI's toolchain.** New Xcode
  templates write the local toolchain's version (6.4 here), and CI's
  `macos-26` image had Swift 6.3, so the first CI run failed on the first
  line of `Package.swift`. It is 6.2, matching the README and the SDK.
- **Xcode schemes can leak API keys.** Environment variables set in a scheme
  (e.g. `OPENROUTER_API_KEY`) are saved in
  `.swiftpm/xcode/xcshareddata/xcschemes/`. The whole `.swiftpm/` directory is
  in `.gitignore` so they never get committed.
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
- **The SwiftLint build plugin breaks the build on any violation.** It runs
  on every `swift build` and Xcode build, and `strict: true` makes violations
  errors, so a stray space blocks running the app. That is intended
  ([0002](../decisions/0002-maximum-backpressure.md)). Xcode's default editor
  settings leave whitespace on blank lines: enable *Settings → Text Editing →
  Editing → Automatically trim trailing whitespace* and *Including
  whitespace-only lines*. The plugin is pinned (`exact:`) to the SwiftLint
  version CI installs from Homebrew; bump both together. Xcode asks once to
  *Trust & Enable* the plugin.
- **swift-format in Xcode** is built in: *Editor → Structure → Format File
  with 'swift-format'* (⌃⇧I) uses [.swift-format](../../.swift-format). There's
  no format-on-save; `make fix` formats everything.
- Timing-based compiler flags (`-warn-long-expression-type-checking`) were
  rejected. They're nondeterministic across machines, which makes for bad
  backpressure.
