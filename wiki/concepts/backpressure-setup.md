---
title: Backpressure setup
summary: Every automated check in this repo, where it runs, and the traps we hit wiring it up.
updated: 2026-10-20
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

Swift Testing suites live in `Tests/TagKitTests`, `Tests/ModelKitTests` and
`Tests/SessionKitTests`, primarily importing the library targets. The startup
contract test also imports the executable to exercise its actual argument parser
(see [0005](../decisions/0005-tag-and-tagkit-targets.md) and
[0015](../decisions/0015-persistent-sessions.md)). The Makefile runs tests and
the coverage gate when `Tests/` exists. All test targets keep the sources'
strict settings and lint plugin; `Tests/SessionProbe` supplies child-process probes.

## Gotchas

- **Share a noncopyable `Mutex` through a `Sendable` reference in task tests.**
  Swift 6.3 rejected `FileLockTests` when a nested `Task` directly captured
  a local `Mutex`, diagnosing a reference to a "mutable let" accessible
  from both tasks. Swift 6.4 accepted the test. The test now stores the
  mutex in a checked `Sendable` final class, like the existing scripted
  browser and fake transport, so tasks share a copyable reference and
  every event read and write still goes through `withLock`. The lock
  ordering assertion and compiler safety checks remain intact.

- **Only use `public import` for modules exposed by public API.**
  `ModelSelection` uses Foundation's `LocalizedError` only in its internal
  `SignInUnavailable` error. Declaring Foundation as a public import failed
  the Swift 6.3 CI build with an unused-public-import diagnostic, promoted
  to an error by the warnings-as-errors gate, even though the local Swift
  6.4 build accepted it. A plain `import Foundation` keeps the dependency
  internal under `InternalImportsByDefault` without weakening the checks.

- **Not every warning fails the build.** `SendableMetatypes` warnings
  ("capture of non-Sendable type 'Decoder.Type' in an isolated closure")
  were printed but didn't fail `swift build` under `treatAllWarnings(as:
  .error)`. Read the build output, not only its exit code. Fixed by making
  the protocol refine `SendableMetatype`.

- **With two test targets, SwiftPM's coverage JSON measures one of them.**
  `swift test --show-codecov-path` points at a `Tag.json` exported against a
  single test bundle (`ModelKitTests` once it was added), so `TagKit` files
  vanished from the gate and it reported about 52 %. `make coverage` now runs
  `llvm-cov export` on the merged `default.profdata` with every
  `*Tests.xctest` bundle as an `-object` and gates that (`all-tests.json`).

- **Tests run by the pre-push hook inherit `GIT_DIR`.** Any `git` command a
  test starts then answers for Tag's repository, whatever its working
  directory: `git rev-parse` in a temporary folder reports a repository, and
  `git init` would reinitialise Tag's. `make check` passed while the push
  failed. Tests don't assert on git answers from temporary folders.
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


### CI task-allocator diagnostics

The first persistent-session PR run compiled on Swift 6.3.3 but the parallel
Swift Testing runner aborted with `freed pointer was not the last allocation`.
The new three-process fixture now uses a throwing task group instead of three
sibling `async let` bindings, retaining its shared start barrier and concurrent
writers/reader assertions. This is a compatibility hypothesis awaiting exact
remote confirmation, not a reason to serialize or disable tests. CI requests
noninteractive sanitized Swift backtraces for any recurrence; macOS capture also
depends on the test executable's signing entitlements. All checks remain unchanged.
See [Swift stack-nesting reports](https://github.com/swiftlang/swift/issues/75501).


A subsequent run still aborted; its sanitized stack identified the default
async environment-probe callback conversion in `SessionController.finishSwitch`.
The callback is now created inside the library initializer, with `nil` as the
public default argument. This avoids exporting the generated async callback
thunk through a public default argument. [Swift issue 92017](https://github.com/swiftlang/swift/issues/92017)
reports a related cross-module default-callback frame mismatch on Swift 6.2.4;
it supports this hypothesis without proving the precise Swift 6.3.3 mechanism.
The task-group change alone was insufficient. Exact CI must validate the callback
repair. A separately reproduced ownership-lifetime failure now has deterministic,
idempotent kernel release after the active task finishes, rather than depending
on ARC destruction timing. No check or test parallelism was weakened.

The next [Swift 6.3.3 run](https://github.com/telip007/tag-agent/actions/runs/39441608663)
executed all 425 test declarations without either earlier failure. Its remaining
failure was a quit-recovery test that sent the second key after an internal
`pauseReason` update, before the UI necessarily offered its explicit quit warning.
That update precedes awaiting the actual agent task's termination. A controlled
task barrier reproduced the ordering locally: paused, still transitioning, and
no quit warning. The test now waits for the rendered warning before confirming
quit, covering both immediate and deliberately delayed task termination. It
retains the same blocked database, timeout bounds and final closure assertion;
application behavior is unchanged.

A later [run](https://github.com/telip007/tag-agent/actions/runs/39444619125)
failed earlier: neither quit-test variant observed `pauseReason` within its
three-second wait. The warning-order reproduction alone therefore does not
explain that runner failure. On failure the test now reports transition/closure,
input/welcome/loading state and its rendered frame, replacing the generated
workspace path with a placeholder. This gathers the next boundary's evidence
without changing application behavior or extending a deadline.

That [diagnostic run](https://github.com/telip007/tag-agent/actions/runs/39447382613)
showed `transition=true`, `closed=false` and no welcome/loading overlay: the quit
key reached the controller, but its blocked save was still pending after three
seconds. Quit recovery now uses a real SQLite trigger that rejects draft writes,
following the existing input/pointer fault fixtures. This makes the write error
deterministic without treating database lock/queue timing as a UI deadline.
Both task-completion variants still require the visible warning and closure,
and verify that the previously saved draft survives. The process-contention and
blocked-write tests continue to exercise real lock waits. Failure diagnostics
retain state flags only; wrapped terminal paths are not reliably redacted by
replacing an unwrapped path string.

A separate real-lock regression verifies that a contended draft write fails
before its lock holder is released and leaves the committed draft intact. This
keeps blocked-write failure coverage independent of native UI scheduling; the
eight-second outer guard bounds that fixture while the UI retains its existing
three-second phase waits.
