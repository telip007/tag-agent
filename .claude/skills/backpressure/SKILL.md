---
name: backpressure
description: Run and act on this repository's automated feedback loop (make check: swift-format, SwiftLint, warnings-as-errors build, tests, coverage gate, wiki lint). Use before declaring any code change done, when a hook reports lint violations, when a build or test fails, or when tempted to relax a rule.
---

# Backpressure

Every check here exists so that mistakes are caught by tools instead of by a
human reading a diff (see `wiki/sources/dont-waste-your-backpressure.md`).

## Loop

1. `make fix` to auto-format.
2. `make check` and read every diagnostic in full. They're written to be
   actionable.
3. Fix the cause, then run again. Repeat until it passes.
4. Only then report the work as done, quoting the final `make check` result.

## Rules

- **Never weaken a check to get green.** That means no `// swiftlint:disable`, no
  `swift-format-ignore`, no lowering `MIN_COVERAGE`, no removing `strictSettings`,
  no `@preconcurrency`/`nonisolated(unsafe)`/`try!` to silence the
  compiler. If a rule is genuinely wrong for this codebase, stop and ask the
  human; if they agree, change the config and record why in
  `wiki/decisions/`.
- A failing test is information. Find out whether the test or the code is
  wrong before changing either.
- Generated code (`**/Generated/`) is excluded from lint and coverage. Fix
  its problems in the generator inputs, never by hand.
