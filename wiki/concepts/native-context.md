---
title: Native context management
summary: Native context retains exact evidence with bounded tools, scoped retrieval and computation, and explicit reversible context views.
updated: 2026-10-20
---

# Native context management

Status: **implemented in [PR #3](https://github.com/telip007/tag-agent/pull/3)**,
which targets main after the persistent-session foundation landed. Normal
session-backed CLI dispatch includes retained evidence and native context tools.
Standalone Agent callers can opt in with NativeContext; the legacy String tool
API remains available. The [implementation ledger](../designs/native-context-plan.md)
records the completed work, and the
[historical research](../designs/native-context-management.md) explains its basis.

## Current verification

The complete feature revision `a8b47d3f5663675df1383d1ccdc97e9b32ec267f`
passed [CI 39469218910](https://github.com/telip007/tag-agent/actions/runs/39469218910):
514 tests in 104 suites, 91.7% coverage over 11,900 source lines, Apple Swift
6.3.3 and unchanged strict/80% rules. Local full gates also passed 514 tests.
The independent whole-branch review's two important findings were reproduced
and fixed, then verified with focused tests and the full gate. The six-case
[contract evaluation](../designs/native-context-evaluation.md) and terminal
checks at 44/80/120 columns establish local behavior, not provider quality or
billing savings. Publication is an open source PR, distinct from merge/release.

Earlier checkpoint paragraphs below record the evidence available at the time;
this result supersedes their pending-gate notes. Documentation revisions follow
the normal local gate and the PR's checks.

## Canonical output evidence

[OutputStore.swift](../../Sources/SessionKit/OutputStore.swift) adds immutable
UTF-8 artifacts to the existing session database. Session UUIDs scope every
read and write. Opaque artifact IDs are values, never file paths. Metadata
retains source, call identity, byte count, SHA-256, capture time and whether
the original source was captured completely.

`saveOutput` rejects the entire write if it exceeds the per-output or
per-session quota. Its hashing and database work run away from the UI actor.
Default storage quotas are 32 MiB per artifact and 256 MiB per session;
these are storage limits, not model context limits. Storage statistics count
canonical bytes, not claimed provider tokens or dollars saved.

`readOutput` reads only the requested bounded byte slice through SQL. It
trims a partial trailing Unicode scalar and gives the next exact offset.
Offsets into a scalar or a limit too short to return any scalar are errors.
Embedded NUL bytes survive. The current per-read ceiling is 16 KiB.

The [version-4 migration](../../Sources/SessionKit/OutputMigration.swift)
creates the artifact table within SessionKit's existing migration and backup
protocol. No second session database, credential store or journal is added.
Existing sessions and raw conversation entries remain authoritative.

## Evidence and limits

[OutputStoreTests](../../Tests/SessionKitTests/OutputStoreTests.swift) use real
isolated databases to test reopening, literal SHA-256, exact Unicode/NUL
content, pagination, session isolation, arbitrary-path rejection and atomic
quota failure. The migration tests emulate old schemas accurately before
reopening the current format. The full `TAG_LIVE_TESTS=0 make check` passed with 417 tests and 92.2%
coverage at this checkpoint, including the direct version-3 upgrade test.
Later integrated feature and remote results are recorded in Current verification above.

Product diagnostics and evaluation are described below. The following sections
describe the capture/admission integration added after that checkpoint.


## Derived retrieval index

[OutputIndex.swift](../../Sources/SessionKit/OutputIndex.swift) adds the
version-5 migration and backfills existing version-4 blobs. Its text chunks
are at most 4,096 bytes, prefer line boundaries and overlap by at least the
maximum 1,024-byte query extent without cutting Unicode scalars. Offsets
always refer to the original immutable blob. The optional FTS5 index uses
Porter tokenization and BM25; original evidence is retained independently.

[OutputSearch.swift](../../Sources/SessionKit/OutputSearch.swift) prioritizes
exact case-insensitive literal matches, including partial code identifiers,
punctuation and NUL-containing text. FTS supplies additional ranked lexical
matches. User query syntax is compiled as literal terms, not executed as
MATCH operators. Every candidate is joined through its session-scoped
artifact; an explicit output ID can narrow, never widen, scope.

A shared UTF-8 text budget bounds returned excerpts. If a literal match is
late in a chunk, a reduced excerpt is centered near it and its offset adjusts
accordingly. Metadata/envelope budgeting is the responsibility of the tool
admission layer; this API's text budget does not pretend to bound an entire
serialized tool response. Retrieval returns selected passages, never a claim
that all input was analyzed.

[OutputSearchTests](../../Tests/SessionKitTests/OutputSearchTests.swift)
exercise late failures, exact citations/ranges, partial identifiers and
punctuation, Unicode budgets, query validation, FTS absence and stemming,
version-4 backfill and identifiers crossing chunk boundaries. The focused
storage/search/migration and child-process suites passed. The full checkpoint
`TAG_LIVE_TESTS=0 make check` also passed: 424 tests and 92.3% coverage.
These are storage/retrieval checks, not completion of tool integration.

## Capture and admission

[NativeContext.swift](../../Sources/TagKit/NativeContext.swift) binds retrieval
to the owned session. [SessionController](../../Sources/TagKit/SessionController.swift)
passes it to each Agent; resuming preserves IDs and a new session changes
scope. Small successful results pass through unchanged. Large results and
failed or incomplete outcomes are stored before journal/UI/model emission.
The JSON preview includes an output ID, byte extent, status, completeness,
head/tail evidence and exact-read instructions. Encoding and escaped Unicode
are included in the 16 KiB content budget; tool groups share 32 KiB.
More than 64 calls in one reply are rejected before any effect. These byte
limits do not estimate provider tokens or gate the conversation history.

[AgentTools.swift](../../Sources/TagKit/AgentTools.swift) uses the optional
[ToolOutcome](../../Sources/TagKit/ToolOutcome.swift) capture seam. Commands
retain exact whitespace and merged stdout/stderr, shell exit codes, signal
status and timeout/completeness. A nonzero exit cannot turn into success
because its output was shortened. Custom String tools also pass admission.
If storage fails after an effect, dispatch stops with the journal's started
boundary intact; recovery never automatically retries unknown effects.

[ProcessCapture.swift](../../Sources/TagKit/ProcessCapture.swift) streams into
an owner-only temporary spool and removes it on all exit paths. Its default
capture limit is 32 MiB and deadline is 120 seconds. Hitting a limit stops
the isolated process group and labels retained evidence incomplete. The
deadline covers the entire run, including commands that close their output
before exiting. Cancellation tears down the group and propagates. This is
process lifecycle isolation, not an execution security sandbox. Invalid
UTF-8 is explicitly unavailable as text, rather than silently replaced.
Only a partial final Unicode scalar at the capture boundary is trimmed.

[FileCapture.swift](../../Sources/TagKit/FileCapture.swift) checks protected
resolved paths, rejects nonregular inputs and reads only up to the capture
limit plus one byte. [FileListingCapture](../../Sources/TagKit/FileListingCapture.swift)
bounds traversal accumulation and the encoded JSON, skips hidden/protected
entries and labels quota/enumeration failures incomplete. Native code_search
retains overflow after line 50; direct legacy String callers keep their
existing behavior.

`read_output` gives exact byte pagination plus hash/provenance/completeness.
`search_output` accepts one query or up to eight and caps the complete JSON
envelope. IDs can narrow the active session, never select a foreign one.
Search is selected evidence, not exhaustive analysis or proof of absence.
Retrieval never archives copies of its own response.

## Gotchas

- A final chunk without a newline must consume the remaining tail. Reusing
  the previous preferred newline with overlap can otherwise loop forever.
  The indexer now checks strict offset progress; the multiline Agent test
  with a final unterminated line reproduces the original defect.
- Output EOF is not process termination. Cancelling a deadline when stdout
  closes leaves a still-running command unbounded. The process test closes
  both streams before sleeping to verify the whole-run deadline.
- Build listing-relative names from enumeration depth and path components.
  Foundation can spell root and child aliases differently even after
  resolving symlinks; subtracting path-string lengths corrupts names.
- Preservation is not autonomous long-term memory. PR #2 supplies canonical
  sessions; later selection of cross-session lessons is a policy layer on
  the same store, not a reason for a competing memory database.

## Capture integration verification

The integrated `TAG_LIVE_TESTS=0 make check` passed with 443 tests
(276 TagKit, 52 SessionKit, 115 ModelKit), 91.8% coverage and the unchanged
80% gate. This includes multiline evidence without a final newline, escaped
Unicode/envelope budgets, cross-session rejection, five-call group budgets,
pre-effect oversized-call rejection and storage failure after a mutation.
Real process fixtures cover >1 MB final errors, signal status, binary
rejection, quotas, deadlines with closed output and cancellation of a child
group. Bounded regular-file and listing fixtures test partial evidence and
resolved protected paths. These are local implementation checks; independent
whole-branch review and exact remote CI remain final-feature gates.

Forced capture cancellation, timeout and quota termination use immediate
SIGKILL for the owned process group. A local OS probe reproduced continuation
of background shell commands in 2/10 SIGTERM-group runs; graceful delivery
can race shell execution. No graceful-shutdown promise or OS sandbox is
implied. Buffers already received are spooled before responding to cancellation.

## File and web indexing

[ContextIndexing.swift](../../Sources/TagKit/ContextIndexing.swift) registers
`index_file` and `fetch_and_index` alongside read/search. They always retain
the original, including small sources, and return a bounded reference with
source, SHA-256, retained byte count, completeness and an untrusted-data
label. A real Agent call also records its originating call ID. Small group
budgets shorten only the returned source label, explicitly marked truncated;
the original label remains in storage. Managed replies bypass recursive
admission, and storage failure stops dispatch rather than continuing the
rest of a group.

`index_file` uses the same resolved protected-path and bounded regular-file
capture as native read_file. Changing the working file never changes the
saved evidence. Quota-limited local files retain an explicitly incomplete
snapshot. Hashes identify captured bytes, not the current state of a path.

[ContextFetch.swift](../../Sources/TagKit/ContextFetch.swift) accepts HTTP(S)
URLs up to 2,048 bytes, without embedded credentials. The default transport
is ephemeral, with no cookies, credential storage or URL cache. Redirects
are validated before following and limited to five. The whole fetch has a
30-second deadline and at most 32 MiB of decoded response-body bytes, also
bounded by the configured artifact quota. Both declared and streamed size
are checked; the underlying task is cancelled on every exit path. Failed
HTTP status, unsupported MIME/charset, invalid UTF-8 and oversized responses
are not indexed. Text, JSON, XML and JavaScript are supported; HTML remains
raw source, with no scripts executed or rendered DOM claimed.

Use search_output to locate passages and read_output to verify exact ranges.
Content from files/web remains data and cannot grant execution permission or
replace trusted instructions. This is active-session source acquisition,
not autonomous discovery across past conversations.

### Exact decoding gotchas

Foundation's `String(data:encoding: .utf8)` strips a leading UTF-8 BOM. A
range starting at a BOM can therefore disagree with its recorded bytes and
hash. Capture, preview and output-range decoding now use failable validating
UTF-8 decoding, preserving BOM scalars as well as NUL. A quota can trim a
valid unfinished final scalar; known-invalid prefixes (overlong encodings,
surrogates and scalars beyond Unicode) must throw, never become empty text.
Real storage/capture regression tests reproduced these failures before the
fixes. No persisted blob or derived index format needs to change.

The focused ingestion checks use real loopback HTTP transport for redirects,
body limits, MIME/encoding rejection, deadlines and cookie isolation. The
credential-redirect test checks the server request count, not just a thrown
error: rejecting only the final URL would already have sent a follow-up
request. File/Agent fixtures verify immutable originals, symlink guards,
partial evidence, long-source envelope budgets, call provenance and stopped
dispatch after native storage failure.

The integrated ingestion checkpoint passed `TAG_LIVE_TESTS=0 make check`:
457 tests (288 TagKit, 54 SessionKit, 115 ModelKit), 91.8% coverage and the
unchanged 80% gate, format/lint/build checks. Independent full-feature review,
exact remote CI and the remaining analysis/continuity/product tasks are
still outstanding.

## Full-artifact computation

`analyze_output` supplies every retained byte of one session-scoped artifact
on stdin to a command, using [ContextAnalysis.swift](../../Sources/TagKit/ContextAnalysis.swift).
[OutputAnalysisInput](../../Sources/SessionKit/OutputAnalysisInput.swift)
checks scope, a maximum 32 MiB input bound, retained length and SHA-256 before
loading the source for execution. Database paths and credentials are not
passed as script inputs. Analysis uses the installed native bash capability,
its working directory and its protected-path policy. It adds no sandbox or
persistent interpreter. A missing or custom shell tool does not silently
acquire a different executor; [ContextCommandExecutor](../../Sources/TagKit/ContextCommandExecutor.swift)
and Agent registration enforce that boundary.

The resulting output is retained even when small. A bounded reply links the
input and output IDs, input byte count, source completeness, exit status,
timeout and output completeness, plus head/tail text. `all_retained_bytes`
describes the available stdin scope: a script must actually read and process
all input before making an exhaustive claim. A partial original capture
remains `source_complete=false`; neither retrieval nor execution upgrades it.
The underlying [ProcessCapture](../../Sources/TagKit/ProcessCapture.swift)
deadline includes a blocked stdin writer as well as stdout/stderr and
process termination.

## Ordered acquisition and scoped batch queries

`batch_execute` runs one to eight explicit commands in order. It validates
all commands, labels and up to eight queries before the first effect. Its
execution deadline defaults to 120 seconds and can be reduced. Each output
is durably stored before starting the next command. Ordinary nonzero exits
remain visible and do not stop later requested commands; use shell `&&`
inside a command for dependent steps that require success. Cancellation,
incomplete capture, timeout and storage failure stop further dispatch.

[ContextBatch.swift](../../Sources/TagKit/ContextBatch.swift) retains a complete
manifest with every command index/label, output ID, byte count, status,
completeness and shell exit/timeout information. Skipped commands are marked
`not_started`. A small reply refers to the manifest and includes bounded
query matches only from that batch's newly captured outputs. It cannot
retrieve a matching older or foreign-session artifact. The manifest is
complete evidence about execution statuses even when some command captures
are explicitly incomplete. Managed output avoids recursive archival.

The same [executor policy](../../Tests/TagKitTests/ContextExecutionPolicyTests.swift)
checks every batch command before the first runs. Tests reproduced both an
accidental shell grant when no shell was installed and bypass of a custom
protected directory; both are now rejected. This is an execution-capability
boundary, separate from the guard's documented limitations as an OS sandbox.
Storage failure after a side effect remains a fail-stop error; never blindly
retry an interrupted batch. The existing canonical journal records its
started boundary so recovery cannot assume effects were absent.

Focused fixtures compute an exact sum over 10,000 records beyond the
preview budget, preserve BOM/NUL input bytes and a failing exit code, reject
foreign or corrupt input before execution, retain ordered writes and all
statuses, exclude older matches, stop after quota/time/cancellation, and
keep the real Agent journal/UI output bounded. A literal-BOM query regression
also fixed the shared SQLite callback: GRDB's implicit BLOB-to-String
conversion stripped the BOM and incorrectly ranked a plain lexical result
ahead of the exact match. Explicit validating decode preserves it.

The full compute checkpoint passed
`env -u TAG_PROMPT_JOB TAG_LIVE_TESTS=0 make check`: 486 tests
(313 TagKit, 57 SessionKit, 116 ModelKit), 91.5% coverage and unchanged
strict/80% rules. This proves local storage, execution, scope and presentation
contracts; compaction, diagnostics/evaluation, independent review and remote verification
were completed in the later checkpoints below.

## Explicit reversible context views

`/compact` changes the next model request, keeping the full canonical journal
and transcript. `/compact off` restores the full request view. It is local,
runs only at a ready writable boundary, and never calls a summarizer or
executes historical actions. It preserves drafts and pending-input review.
The state bar identifies an active compacted view and its restore command.
There is no automatic history truncation or local byte-as-token rejection;
provider context errors retain the existing retry, model and new-session
choices. A view with all critical content pinned may still be too large.

[SessionContextProjection](../../Sources/SessionKit/SessionContextProjection.swift)
policy version 1 pins every user message and correction, every failed tool
group and the most recent eight assistant/tool groups. Older successful
groups are omitted only as whole groups, including their opaque replay.
Retained groups keep all call IDs, results, signatures and encrypted reasoning
unchanged. Historical entries recorded with `failed=false` cannot acquire
trustworthy exit status from arbitrary text; an older failure may therefore be
omitted by explicit compaction. Use `/compact off` or exact history retrieval
when examining such sessions. The manifest records canonical sequence references, avoiding a
second copy of large historical bodies. `search_history` finds readable
active-session decisions, and `read_history` pages exact stored event JSON;
its offsets address that JSON envelope rather than raw stdout. Original
large tool evidence remains separately available through read_output.

A bounded harness notice links the manifest and explains retrieval. When
omitted visible content is no larger than the notice plus a 256-byte margin,
compaction remains disabled instead of growing a tiny request. This compares
text bytes, not provider tokens or monetary savings. All user messages and
failed groups are preserved even if they alone exhaust a model window.

[SessionCompaction](../../Sources/SessionKit/SessionCompaction.swift) saves the
manifest before an explicit canonical projection event. Its append checks a
fresh cutoff, protocol completeness, same-session source, manifest hash,
policy version and exact omitted group references. A crash/cancellation
between artifact save and event commit may leave an unused manifest, never
an applied half-view. The stored summary agrees with the latest event on
load; stale, foreign or corrupted views fail closed. The additive event kind
uses the existing versioned envelope; older binaries reject unknown kinds
instead of silently misreading them. No second database or schema migration
is needed for this event extension.

[ContextRequestProjection](../../Sources/TagKit/ContextRequestProjection.swift)
builds a fixed request prefix at the explicit epoch; new live messages append
normally. Model changes update the system prompt while preserving the valid
retained groups. Cached prefixes are not rewritten every tool turn. Usage
becomes unknown at the view change rather than claiming newly measured
savings; canonical provider cost remains intact. A standalone Agent without
native retrieval keeps its full history, rather than hiding records it cannot
retrieve. Normal session-backed CLI execution includes scoped history tools.

Real store tests cover reopen/restore, tiny-history no-op, pending/interrupted
groups, cancelled/quota-limited saves, stale and foreign references, manifest
corruption and unsupported policy versions. Request tests pin corrections
and failures, check complete groups, use the view in a real Agent loop and
serialize retained multi-call replay through Anthropic, Responses and Gemini
adapters. A native terminal test types `/compact` and `/compact off`, checks
the rendered state and verifies commands never become model input.

The full compaction checkpoint passed
`env -u TAG_PROMPT_JOB TAG_LIVE_TESTS=0 make check`: 504 tests
(323 TagKit, 65 SessionKit, 116 ModelKit), 91.6% coverage and unchanged
strict/80% rules. Diagnostics/evaluation, independent review and remote verification were
completed in the later checkpoints below.


## Diagnostics and local reports

`context_stats` measures active-session retained artifact count/bytes,
incomplete count and committed tool-result count/bytes, with recorded failure
count and active compact-view status. Last provider input/cache-read/cache-write
tokens remain separate nullable fields. Retrieval replies count as presented
results when committed; diagnostics never recursively retain their own output.
These volumes are not compression ratios or estimates of billing savings.

`context_doctor` reads SQLite's actual linked version and quick_check result,
validates canonical history/projection, distinguishes pending recovery from
corruption, checks artifact IDs/lengths/UTF-8/SHA-256 and checks derived chunks
and available FTS rows against retained bytes. It reports literal-only fallback
when FTS5 is absent. It does not repair indexes, recover turns or rerun effects.
Checking all evidence can take time; it scans one artifact at a time within the
store read transaction. Database paths and credentials are not included.

`/context`, `/context doctor` and `/context off` display or hide a local status
report without a model request or canonical user message. Switching sessions
clears it. They are snapshots, not live billing meters. The deterministic
[evaluation](../designs/native-context-evaluation.md) records native contract
comparisons and their limits.

## Upstream concept coverage

The reference is [Context Mode 1.0.169](../sources/context-mode.md), pinned at
`b31c7ee853cb9ea76121e24d368599390972a997`. This is an original implementation.

| Upstream capability | Native equivalent or deliberate boundary |
| --- | --- |
| execute / output filtering | Guarded native bash, universal result admission, exact read/search; batch queries provide intent filtering even for one command. |
| execute_file / data processing | index_file then analyze_output streams all retained bytes to stdin; installed interpreters run through bash. No file contents need enter the model prompt. |
| batch_execute with questions | Ordered capture, durable manifest, statuses and queries scoped only to newly acquired batch artifacts. |
| index / fetch_and_index | Immutable file and streamed HTTP UTF-8 snapshots with provenance, quotas and completeness. Raw HTML is retained as text; browser rendering is outside this tool. |
| search / citations | Literal-priority matching plus optional Porter FTS5/BM25, exact byte offsets, SHA-256 and scoped IDs. No claim of equivalent fuzzy/trigram/reranking recall. |
| stats / doctor | Separate local volumes and provider metrics; read-only journal/evidence/index/engine checks. |
| session continuity / resume | PR #2 canonical journal, explicit resume, typed recovery and scoped history retrieval. |
| compact / resume snapshots | Explicit reversible request projection pins users, recorded failures and recent complete groups; no lossy generated summary. |
| routing / data-flow guidance | Harness admission applies across providers; tool guidelines distinguish selected search from whole-input computation and retrieval from rerunning effects. |
| plugin install / upgrade / hooks | Omitted: native compilation/normal application updates and typed harness events replace host integration. |
| hosted analytics | Omitted: local measured diagnostics need no external telemetry service. |
| persistent REPL | Omitted: retained artifacts preserve data, while each command has an explicit bounded lifecycle and the installed shell's authority. A resident interpreter would add hidden mutable state and recovery obligations. |
| recursive LLM / learned memory | Deferred: research-dependent policies require quality and cost evaluation. Deterministic exact storage, retrieval and computation need no extra model. |

No separate memory backend is introduced. Selective cross-session discovery,
forgetting and promotion remain future policies over canonical evidence;
active-session context tools never silently widen their scope.


The integrated diagnostics/evaluation checkpoint passed
`env -u TAG_PROMPT_JOB TAG_LIVE_TESTS=0 make check`: 511 tests
(327 TagKit, 68 SessionKit, 116 ModelKit), 91.6% coverage, with unchanged
strict checks and 80% minimum. This includes the rendered local reports at
44/80/120 columns. Independent whole-branch review and exact remote CI remain
separate gates before completion.


## Independent review refinements

The fresh whole-branch review identified two important gaps. Spool write and
read/seek failures after an effect now use the same fail-stop storage error as
artifact retention failures. They propagate through ordinary capture, analysis
and batches; the first call remains unresolved for unknown-effect recovery,
and later tool calls and inference stop. Expected invalid-UTF-8 rejection stays
a distinct text-format error. An internal spool I/O seam supports actual
post-effect fault injection without global state or a real full disk.

Doctor now uses the indexer's deterministic chunk layout, including overlap,
to compare every stored chunk and offset. Checking only existing rows or full
byte coverage misses partially deleted indexes and boundary-query damage.
Both FTS and literal-only routes share this validation. Diagnostics remain
read-only and do not rebuild missing evidence.


After the review fixes, the full unchanged gate passed with 513 tests
(328 TagKit, 69 SessionKit, 116 ModelKit) and 91.7% coverage. Both findings
were reproduced before their fixes, then the focused 23-test set and full
suite passed. Remote CI for the published final commit remains a separate gate.


## Remote integration checkpoint

The first feature CI run, [39460549780](https://github.com/telip007/tag-agent/actions/runs/39460549780)
at `f163455`, failed five assertions in its combined test process. It exposed
a transport/harness timeout race: either deadline now reports the same ToolError,
while cancellation remains distinct. A short URLSession resource deadline
reproduced the raw transport error before the correction.

Process deadline fixtures now arm a controlled test clock after the actual
child reaches the exercised state: captured output, closed output streams or
blocked stdin. Production still starts its deadline at invocation with the same
default Task.sleep. Tests assert timeout and absence of the child's completion
effect, rather than assuming a loaded shared runner schedules launch and teardown
within one second. The descendant cannot perform its escape effect until the
caller explicitly permits it after run returns. Default deadline execution also
remains exercised by the batch integration test.

At that checkpoint the remote Python byte-analysis mismatch was unexplained.
Its local test passed; the assertion was changed to expose captured text on failure. The
focused 26-test integration set passed locally after these changes. Final full
local and remote gates remain required; the first remote failure is historical
evidence, not a green feature result.

The integrated local gate then passed 514 tests (329 TagKit, 69 SessionKit,
116 ModelKit) at 91.7% coverage with unchanged strict checks. This does not
resolve the outstanding remote byte-analysis observation; the next remote run
must either reproduce it with the captured value or establish its new result.


The next [CI run 39463461476](https://github.com/telip007/tag-agent/actions/runs/39463461476)
at `1d78a1f` passed the deadline fixtures and failed only the Python probe.
Its improved diagnostic showed the exact expected `efbbbf6100` bytes, preceded
by Swift runtime stderr warnings: CI enables SWIFT_BACKTRACE, and the system
Python launcher reports that backtraces are unsupported for privileged executables.
A local `/usr/bin/python3` counterfactual reproduced warnings with that setting
and clean exact stdout without it; both variants exited 7 with identical stdin
hex. The capture pipeline correctly preserved merged stdout/stderr.

Only this exact-byte fixture's Python invocation now removes SWIFT_BACKTRACE.
Production environment inheritance and stderr capture stay intact, and the
same strict output equality, failure status and partial-source assertions remain.
This isolates the probe from the test harness's debug configuration.

The full local gate with CI's SWIFT_BACKTRACE setting enabled passed 514 tests
(329 TagKit, 69 SessionKit, 116 ModelKit), 91.7% coverage and unchanged strict
checks after the fixture isolation. The correction still requires its exact
published remote check before the feature goal is complete.


[Run 39465809146](https://github.com/telip007/tag-agent/actions/runs/39465809146)
at `09e57c8` confirmed the exact-byte analysis correction and passed all but
the stalled-fetch elapsed assertion. That test observed 2.55 seconds while
resuming on the main actor shared with terminal fixtures. Its observation now
captures elapsed time inside a concurrent probe, before the caller's actor hop.
The same 100 ms request deadline and two-second assertion remain; an isolated
URLSession additionally verifies requests are canceling/completed before fixture
cleanup. This changes the measurement boundary, not production timeout behavior.
The focused 28-test set, including terminal fixtures, passed locally with CI's
backtrace setting enabled; exact remote verification remains required.

The full local gate with the revised fetch observation passed all 514 tests
(329 TagKit, 69 SessionKit, 116 ModelKit) at 91.7% coverage, with CI's debug
setting enabled and the same strict checks. Its remote result remains pending.


## Published session foundation

PR #2 landed on main as `48615e2` during feature verification. Its final branch
commit `d38e007`, the previously integrated `f7cc679` and the published main
commit have the identical tree `6cea9262dca06e97b9b23e9c2b567aea53597e61`.
The feature branch joins the published main history while preserving its native
source delta exactly; PR #3 now targets main. This is history alignment after
squashing, not a second session implementation or new source divergence.
