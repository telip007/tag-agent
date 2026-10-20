---
title: Persistent sessions
summary: Proposed local session storage, reliable continuation, switching and explicit user references, with automatic memory retrieval deferred.
updated: 2026-10-20
---

# Persistent sessions

Status: approved for implementation. The user requested the full implementation
and a GitHub PR. Based on repository commit `5268e13`; progress is tracked in
the [execution plan](persistent-sessions-plan.md) and
[session storage](../concepts/session-storage.md).

This page preserves the approved proposal. Later implementation refinements in
[0015](../decisions/0015-persistent-sessions.md#review-refinements) replace the
planned FTS ranking with literal matching and make context fit provider-authoritative.

## What we are building

Save a conversation so the user can close Tag, explicitly reopen it with
`--resume` or the session navigator, and continue where they left off. Support several named sessions, switching between them, and
explicitly referring to another session from the current conversation.
Retrieve bounded, attributable excerpts rather than merging entire histories.

The user explicitly narrowed this phase: autonomous session discovery belongs
with later work on memory, dreaming and consolidation. These features share a
storage foundation, but have different policies. This phase supplies a durable
record and user-directed access; it does not decide what the agent should
remember or when it should search independently.

Other exclusions: cloud sync, background agents, branching/revert, automatic
summaries, vector embeddings, importing other agents' histories and filesystem
rollback. Session restoration restores conversation state, not old file contents.

The user's request to implement this design approves the proposal below.
The [execution plan](persistent-sessions-plan.md) tracks implementation and
verification, including the engine compatibility gate.

## Baseline seams and constraints before implementation

- [Agent.swift](../../Sources/TagKit/Agent.swift) creates `ConversationState`
  inside `run()`. It owns the model messages, date annotation state, selected
  model, stable provider session UUID, token metrics and accumulated cost.
  `/clear` currently discards these and rotates the UUID.
- [Conversation.swift](../../Sources/ModelKit/Conversation.swift) holds the
  provider-neutral messages. Assistant text alone is insufficient: tool IDs,
  arguments, results and opaque `ReplayItem` payloads must survive. Several
  types are not `Codable` yet. Preserve nil versus empty and array ordering.
- [ChatSession.swift](../../Sources/TagKit/ChatSession.swift) separately owns
  the visible transcript, typed-ahead queue and input history. UI events omit
  some model data; they cannot be the sole persistence source.
- [ChatView.swift](../../Sources/TagKit/ChatView.swift) owns one agent task
  and exits when it ends. Switching needs a session controller above this task,
  rather than starting two loops against the same input continuation.
- [Tag.swift](../../Sources/Tag/Tag.swift) always creates a fresh session.
  [Storage.swift](../../Sources/ModelKit/Storage.swift) persists settings and
  credentials, using whole-file JSON replacement and process locks. That is
  suitable for small configuration, but rewriting all history per turn is not
  the proposed session store. Its unreadable-file-as-empty behavior must not
  be copied for conversations.
- Preserve [prompt caching](../concepts/prompt-caching.md): stable UUID and
  exact historical model input, including date annotations and signed replay.
  Prompt changes after an upgrade can cause a cold cache; persistence cannot
  guarantee a provider cache hit.
- Keep macOS 15 and Swift tools 6.2, strict concurrency and memory safety,
  warnings as errors, existing lint rules and the 80% coverage gate.
  [Backpressure](../concepts/backpressure-setup.md) documents why local success
  on a newer compiler does not establish CI compatibility.

## Storage recommendation and alternatives

Recommend SQLite through GRDB, with incrementally appended conversation
entries and indexed session metadata in one authoritative database. Save a
semantic boundary in one transaction; never rewrite the full conversation on
each streamed token. Use explicit versioned JSON payloads inside relational
rows to retain model data without a table per provider format.

| Option | Strength | Cost for this scope | Recommendation |
| --- | --- | --- | --- |
| One JSON snapshot per session | Simple inspection and replacement | Rewrites growing history; separate indexing and tool recovery logic | Reject for the primary store |
| Append-only JSONL | Simple export and sequential append | Torn-tail handling, concurrency and metadata/search consistency become application code | Credible benchmark baseline and future export format |
| JSONL plus a SQLite index | Inspectable log and fast discovery | Two stores to reconcile after interrupted writes | Avoid that complexity for Tag's first implementation |
| SQLite plus GRDB | Atomic entries/metadata, migrations, bounded queries | Dependency and engine compatibility must be verified | Preferred |
| SwiftData/Core Data | Native object persistence | Less direct control over this ordered protocol log and search boundary | No demonstrated advantage here |
| Remote or vector database | Shared/semantic retrieval | Service operations, network cost and policies outside the requested feature | Defer |

Current primary-source comparisons: pi uses append-only JSONL entries with
parent links; Codex records canonical JSONL rollouts and also consults SQLite
for listing, including reconciliation/fallback paths. These establish useful
patterns, not a universal performance winner. See the pinned sources below.
Tag does not need their branching or dual-store recovery machinery yet.

GRDB `v7.11.1` is the latest release reported by its release API during this
research. Its Swift 6.1 floor fits the package's declared tools floor. It
provides asynchronous access, migration facilities and `DatabasePool` for WAL
read/write concurrency. The exact resolved package must be inspected and
compiled under Tag's flags before acceptance. No dependency is added by this plan.

### Important compatibility gate: WAL is conditional

SQLite documents a rare WAL-reset corruption bug fixed in 3.51.3 and later,
with fixes also backported to 3.44.6 and 3.50.7. Concurrent connections that
write/checkpoint are relevant to multiple Tag processes. An Apple version
string alone does not establish whether its library includes that fix.

Use this concrete initial policy:

1. Start with GRDB's system SQLite and `DatabaseQueue`, rollback journal
   `DELETE`, `synchronous=FULL`, foreign keys enabled and a 2-second busy
   timeout. This is the portable correctness baseline, including concurrent
   processes. All database access is asynchronous from the UI's perspective.
2. Evaluate WAL with `DatabasePool` only after the linked runtime is proven
   fixed and all supported binaries opening that store use a compatible
   engine. Read version/source ID and test FTS5 using the application connection;
   a separate `sqlite3` executable does not prove what the app links.
3. Do not automatically flip a shared store between journal modes on startup.
   WAL adoption is a deliberate migration/packaging decision made after the
   compatibility and performance experiment. If required, plan a supported
   bundled-engine route separately. GRDB's documented custom SQLite recipe
   explicitly warns about SwiftPM compatibility; adding a random SQLite
   package is not evidence that GRDB links it.

In WAL experiments retain `synchronous=FULL`; benchmark `fullfsync=ON` on
macOS as the stronger flush baseline and disclose the durability assumptions.
Do not obtain a speed claim by silently weakening acknowledged-save durability.
Keep default checkpoint behavior initially; tune only from measurements.
WAL is for a local disk, not a network-mounted store.

This gate qualifies the WAL optimization, not the recommendation to use SQLite.
No backend is described as the most efficient until the Tag workloads below
have been measured with equivalent durability.

## User behavior

### Starting and continuing

- Plain `tag` always starts a new session in the exact current workspace.
  Closing and reopening must never implicitly resume the previous conversation.
  Use a canonical directory identity, resolving symlinks, without merging sibling
  Git worktrees or repositories. Last-opened metadata does not select startup.
- `tag --new` is an explicit equivalent. `tag --resume <id>` opens a specific
  saved session; accept a unique ID prefix and reject ambiguous prefixes explicitly.
  The session navigator also supports explicit continuation.
- A session binds its execution directory. A missing or different directory
  permits read-only inspection but no model/tool execution until the user opens
  Tag there. Merely viewing or referencing a session never changes directories.
- Restore the saved model and reasoning effort. If unavailable, require a
  user model choice; do not silently change provider or send saved content.
- Opening a session restores state and waits. It never automatically sends a
  paid request, drains queued messages or runs a tool left over from a crash.
- Keep a stable provider session UUID through resume/switch. A new session
  gets a new UUID. Historical user messages retain their exact dated model
  text; the date tracker resumes from saved state, so a new day is annotated
  only on a new message.
- Re-probe the workspace on reopening. Preserve the recorded prompt/context
  for history; build the current system prompt from current trusted instructions
  and tools, recording a context revision when it changes. Never execute old
  policy text just because it was stored. An unchanged prompt stays identical;
  a changed prompt deliberately invalidates that cache prefix.

### Session management

- `/sessions` opens a searchable recent-session picker; `/session <id>`
  switches directly. Picker rows show title, ID prefix, directory, model and
  last activity. Default to the current workspace; an explicit all-workspaces
  view is available for inspection/reference, subject to directory binding.
- `/new` creates a session; `/rename <title>` changes its title. Default title
  comes from the first user message, with whitespace collapsed and 80-character
  truncation, avoiding an extra model request.
- `/clear` starts a new empty session and keeps the old one recoverable.
  Explain this changed behavior in command help; clearing no longer deletes
  the only copy of a conversation. Storage deletion is a separate future UI.
- Switch only at a ready-for-input boundary in this phase. During inference
  or tool execution, report that switching becomes available after the turn;
  do not cancel a shell command or invisibly move a queued message.
- Draft input and accepted typed-ahead messages belong to their session.
  Save draft input on explicit switch/clean exit, without claiming keystroke
  crash durability. Accepted queued messages are durable immediately and
  restored as pending for review, not automatically sent on reopen.
- One writer owns a session across processes. Another process may inspect it
  and open a different session, but cannot take over an active conversation.

### Explicit reference from another session

Proposed syntax: `/reference <session-id> [query]`. This is a local command,
handled before sending model input. It authorizes reading that one source
session. No free-form `@` parsing that can mistake code or an email for consent.

- With a query: rank matching readable entries from the named session using
  FTS5 if supported, with a bounded literal-search fallback otherwise.
- Without a query: present the latest completed exchange as a preview. The
  user can refine the query or choose an entry range before attaching.
- Attach at most 5 excerpts and 16 KiB UTF-8 total, including labels; trim at
  valid character boundaries and show truncation. These are proposed ceilings,
  not a claim about token count. Check remaining model context separately.
- Source labels include immutable session UUID, entry sequence/range, title,
  timestamp and role. Persist the exact attached excerpt and source coordinates
  in the destination. Later source changes cannot silently rewrite what the
  destination model previously saw.
- Preview the selected content and let the user attach it with their next
  message. The command itself does not call the model. A pending reference is
  saved with the destination input and cannot leak into another session.
- Render attachments distinctly. Send excerpts as quoted user-provided data,
  never system instructions or a forged assistant/tool history. Cite their
  session/entry labels in answers that use them.
- Only the explicitly selected session is eligible. Self-reference, no match,
  malformed/ambiguous IDs and unsupported versions produce local feedback;
  no widening to all sessions and no fabricated summary.
- Search only readable user/assistant text and tool names/results. Exclude
  system instructions, opaque replay, encrypted reasoning and failure internals.
  A reference is historical evidence; it does not import approvals, tool
  capabilities or authority to act in the source workspace.

Do not expose model-callable `search_sessions`/`read_session` tools in this
phase. The future memory feature can build policy-controlled tools on the same
read APIs. It must separately decide access scope, proactive search triggers,
relevance budgets, retention and consolidation. FTS is an index, not memory.

## Persistence contract

Store at `ConfigDirectory.url()/sessions/sessions.sqlite`, outside the working
repository and under the existing protected config tree. Keep credentials in
their existing files. Use owner-only directory/file permissions (0700/0600),
including journals/sidecars and per-session lock files; verify rather than
assuming defaults. Test alternate config roots and symlink protection. Saved
conversations can contain user-provided secrets even though credentials are
never deliberately copied into them. No encryption-at-rest claim in this phase.

Proposed schema, with migrations and explicit payload version 1:

| Table | Contents and invariants |
| --- | --- |
| `sessions` | UUID primary key, canonical workspace, title, creation/update/last-opened times, model/effort, provider UUID, context revision, next sequence, usage totals and saved date-tracker state |
| `entries` | `(session_id, sequence)` unique, kind, timestamp, payload version, explicit JSON payload; ordered user/assistant/tool/control records plus presentation metadata |
| `pending_inputs` | Stable input ID, session ID, order, raw text and reference attachments; atomically promoted into a user entry when consumed |
| `workspace_state` | Canonical workspace key and last-opened session ID |
| `session_drafts` | Per-session unsent prompt and pending reference preview, saved on clean boundaries |
| `entry_search` | Rebuildable FTS5 readable-text projection keyed to canonical entries, when FTS5 is available |

Index `(workspace, last_opened_at, id)` for discovery. Use keyset pagination,
50 session rows per page. Hydrate only the chosen session's model history;
initially load 100 visible transcript blocks and page older blocks on demand.
The model still needs its full valid context: do not truncate it silently to
meet a UI performance target. If the restored conversation exceeds the selected
model's window, explain and require an explicit user choice; automatic
compaction belongs to later work.

`entries` is authoritative, including context revisions; searchable text and
cached session totals are projections updated in the same transaction and
rebuildable. Do not duplicate whole-history snapshots on every append.
JSON encoding uses explicit role/kind/version tags, not synthesized associated
enum layouts as an undocumented disk format. Unknown versions fail closed for
continuation, while preserving data for diagnostics/export. Never treat a
decode/migration failure as an empty successful session.

Save these boundaries before the next external action:

1. Accepting user input: persist raw input and attachments before acknowledging
   acceptance. Atomically consume a pending item and append its exact dated
   model message before making an inference request.
2. Completed inference: commit the complete assistant message, usage and
   selected-model metadata before acknowledging it as saved or running tools.
   Streaming deltas may be displayed but are not committed model history.
3. Each tool: commit a start marker with call ID before execution, then its
   output/failure and display metadata before executing the next tool or
   submitting another model request. Never hold a database transaction over a
   model request or tool execution.
4. Model/context changes, switching, clear/new and clean exit: await their
   local saves. Save failures pause new inference/tool work with visible retry
   guidance; never silently fall back to an ephemeral conversation.

On restart, incomplete streamed output may be absent; label the interrupted
request. An acknowledged user input remains available. A saved assistant tool
call without a committed result has unknown effects, including the window
after a real side effect but before its result saved. Never replay such tools.
Append an explicit interrupted/unknown-effect result for each unresolved call
to keep provider history valid, distinguish calls never started from calls
started, show the recovery notice and wait for the user. The next model can
inspect current files if asked. Exactly-once filesystem effects are not promised.

Persist enough presentation metadata with canonical records to reconstruct
raw user text, reasoning, replies, tool state/output and edit summaries.
Do not serialize `LiveBlock`, continuations, `ActiveModel`, closures or
`ContinuousClock.Instant`. Store wall-clock timestamps and measured elapsed
durations as values; restored tools are never shown as still running. Restore
session cost and latest usage without double counting; reset stale cache counts
when the restored model or prompt changes.

Use one process-held nonblocking advisory lock per active session, acquired
before hydration, released on switch/exit and by the OS on process death.
SQLite transactions coordinate different sessions sharing the database.
Avoid expiring leases that allow two owners after a long suspension. Keep
reads short, bind SQL parameters, and compile FTS user input as literal terms
rather than passing arbitrary MATCH syntax. Session IDs are values, not paths.

Schema migrations are serialized across processes, forward-only and backed up
before changes using SQLite's online backup API through GRDB. Never copy only
the main database while live journal/WAL state exists. Corrupt/too-new stores
are preserved and reported, not recreated. Network filesystems are unsupported.
No auto-pruning. Export/retention/deletion UI can follow after the core feature;
the storage API must preserve the ability to add them without a new log format.

## Integration sequence and acceptance gates

Each stage updates the affected project wiki and passes the unchanged checks.
Names below are proposed new files; existing files are linked above.

1. **Engine compatibility and performance evidence.** Evaluate GRDB 7.11.1
   with exact package resolution, existing compiler flags and CI toolchain.
   Compare rollback `DatabaseQueue`, patched-runtime WAL `DatabasePool`, and
   an append-only JSONL baseline with equivalent acknowledged-write flushing.
   Record linked SQLite identity, FTS5 capability and migration support. Resolve
   the WAL packaging question before adopting WAL; rollback remains the safe
   first-release configuration. No dependency-policy or compiler-check bypass.
2. **Lossless durable records.** Add `SessionKit` and `SessionKitTests` targets;
   only SessionKit depends on GRDB. TagKit depends on SessionKit, which depends
   on ModelKit, keeping UI/provider code independent of SQL. Add
   `SessionRecords.swift`, `SessionCodec.swift`, `SessionStore.swift`,
   `SQLiteSessionStore.swift`, `SessionMigrations.swift`, `SessionOwnership.swift`.
   Round-trip every message/replay format, nil/empty field, usage value and
   presentation record. Test ordered atomic appends, process contention,
   pending-input promotion, version rejection and migration backup/reopen.
3. **Recoverable agent lifecycle.** Extract `ConversationState` from Agent.swift
   into its own file and introduce a `SessionController` that owns a loaded
   session and exactly one agent task. Add awaited durable boundaries to Agent;
   keep UI deltas separate. Test process termination before/after user saves,
   assistant saves and each tool start/result, including two calls where the
   first finished and the second did not. Assert no automatic inference on
   restore, no tool rerun, valid call/result pairing, exact replay and UUID/date
   preservation, failure-to-save pause and usage not counted twice.
4. **Continue and switch in the CLI/TUI.** Wire Tag startup flags and controller
   into ChatView, add `SessionCommand.swift` and `SessionPicker.swift`, and
   hydrate ChatSession from stored records. Test fresh default startup, explicit new,
   unique/ambiguous resume IDs, clear-as-new, unavailable model, directory
   mismatch, busy-switch refusal, session-local draft/queue, writer ownership
   and transcript pagination. Verify actual Stipple rendering and keyboard
   selection, with no double agent task and no cross-session late events.
5. **User-directed references.** Add `SessionReference.swift`,
   `SessionSearch.swift` and a local `SessionReferenceFlow.swift`; wire
   `/reference` before ordinary message submission. Test literal search,
   fallback without FTS5, no-match/ambiguous IDs, source citations, immutable
   copied excerpts, 5-result/16-KiB limits, Unicode trimming, model-window
   overflow, pending-reference isolation and hostile instructions treated as
   quoted data. Assert unrelated sessions and opaque replay never enter the
   request, and no automatic lookup tool is registered.
6. **Verify the integrated experience.** Use deterministic scripted models and
   separate child processes for crash/locking tests; paid provider requests are
   unnecessary. Run `TAG_LIVE_TESTS=0 make check` and the exact CI-toolchain
   build, retaining all strict checks. Add an approved architecture decision and
   a session-storage concept page describing the final behavior and commands.

### Proposed measurement budgets

Use release builds, generated non-sensitive data and reproducible seeds.
Benchmark a growing active session (1,000 and 10,000 entries), discovery across
10,000 sessions, 100,000 searchable entries and tool results up to the existing
1-MB output cap. Measure cold and warm runs separately, peak memory, bytes
written, commit count, database/index size, time to usable input and p50/p95
latencies. Compare a concurrently reading process and two independent writers.

Initial targets: p95 durable append under 20 ms for a 4-KiB entry and under
100 ms for 1 MiB; metadata-page lookup under 50 ms warm; first 100 visible
blocks under 100 ms warm, excluding full model-history load; bounded reference
query under 100 ms warm at 100,000 entries. Zero synchronous database calls
or whole-history encoding in the MainActor streaming callback. Report full
context hydration separately and verify append work does not grow with the
pre-existing conversation length. These budgets are acceptance proposals,
not observed results or universal hardware guarantees.

If a target fails, inspect measured costs before changing architecture; do
not lower durability or hide context truncation to pass it. Performance reports
belong in the project wiki without personal paths or machine identifiers.

## Sources checked on 2026-10-20

- [GRDB 7.11.1 release](https://github.com/groue/GRDB.swift/releases/tag/v7.11.1)
  and [pinned README](https://github.com/groue/GRDB.swift/blob/v7.11.1/README.md):
  requirements, database connections, migrations and concurrency facilities.
- [GRDB custom SQLite builds](https://github.com/groue/GRDB.swift/blob/v7.11.1/Documentation/CustomSQLiteBuilds.md):
  system-library default and the documented SwiftPM limitation.
- [SQLite WAL](https://sqlite.org/wal.html), especially sections 2 and 11:
  concurrency, checkpointing, durability tradeoffs and the WAL-reset fix.
- [SQLite PRAGMAs](https://sqlite.org/pragma.html): synchronous/fullfsync,
  busy timeout and journal configuration. [FTS5](https://sqlite.org/fts5.html):
  readable-text indexing, MATCH syntax, ranking and external-content maintenance.
- [SQLite online backup](https://sqlite.org/backup.html): consistent live backup.
- [pi session manager](https://github.com/badlogic/pi-mono/blob/73f8de80bc87021375f8b525292ac07492253002/packages/coding-agent/src/core/session-manager.ts):
  append-only JSONL, versioned entries and parent-linked sessions.
- [Codex rollout recorder](https://github.com/openai/codex/blob/014489466a1739c2c563cdfe57880c2c7c8680e3/codex-rs/rollout/src/recorder.rs):
  canonical JSONL and SQLite-backed listing reconciliation.

## Planning verification before implementation

At the planning checkpoint no store, migration or dependency change existed.
Current implementation evidence belongs to the linked execution plan and
concept page. Engine performance and model-facing resumption were unmeasured.
The isolated baseline passed `TAG_LIVE_TESTS=0 make check`: 307 tests across
both test bundles and 91.5% line coverage, with unchanged strict checks. The
new documentation also passed `make wiki-lint` (37 pages).

A separate read-only builder check found no important unanswered product
questions or scope contradictions. It confirmed that engine/toolchain
compatibility and measured performance remain implementation gates; WAL can
remain deferred while the rollback-journal baseline proceeds. That review is
design feedback, not approval of an implementation or an efficiency claim.
