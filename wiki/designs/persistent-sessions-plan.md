---
title: Persistent sessions implementation plan
summary: Execution tasks and verification gates for durable sessions, continuation, switching and explicit references.
updated: 2026-10-20
---

# Persistent sessions implementation plan

> For agentic workers: use superpowers:executing-plans and test-driven
> development. Execute every task, then obtain a fresh whole-branch review.

**Goal:** Implement [the approved session design](persistent-sessions.md) and
open a verified GitHub PR, without autonomous session discovery.

**Architecture:** SessionKit owns versioned records, a GRDB-backed database
and ownership locks. TagKit owns hydration, one foreground agent task, UI
commands and explicit reference selection. ModelKit retains provider-neutral
messages and gains an explicit stable message encoding.

**Stack:** Swift tools 6.2, macOS 15, GRDB 7.11.1, system SQLite with rollback
journal, Swift Testing and Stipple. WAL stays gated on a verified fixed engine.

## Global constraints

- Preserve all strict checks and the 80% coverage minimum; `make check` passes.
- Persist before inference/tool side effects; never replay unresolved tools.
- Restore exact dated model messages, replay data, stable UUID and usage.
- A restored session waits; queued inputs never dispatch automatically.
- Explicit references are bounded quoted data; no autonomous lookup tools.
- Keep credentials separate; use protected owner-only storage outside projects.
- Public project documentation contains no personal paths or machine details.
- No merge, deployment or release; publication ends with the requested PR.

## Review focus

- Crash windows around a completed side effect and its uncommitted result.
- Two processes opening the same session or migrating the same store.
- Late events, pending input and references crossing session switches.
- Unknown versions or corrupt data being mistaken for empty history.
- Model/prompt changes, oversized history and stale cache/usage accounting.

### Task 1: Lossless protocol records and engine compatibility

Files: `Sources/ModelKit/MessageCoding.swift`, `Conversation.swift`,
`Sources/SessionKit/SessionRecords.swift`, `SessionEvent.swift`,
`SessionCodec.swift`, `Package.swift`, `Package.resolved`, and matching tests.

Interfaces: `Message`, `AssistantMessage`, `Usage` conform to Codable;
Message uses explicit `role` tags. `SessionEvent` is a versioned tagged record;
`SessionSummary` stores UUID, workspace, title, model/effort and timestamps.
`PendingInput` stores a stable UUID, text and references. `SessionCodec` rejects
unknown versions and round-trips opaque replay, nil/empty and Unicode.

- [x] Write and observe failing round-trip and unknown-role/version tests.
- [x] Implement the explicit codec and records; inspect the exact GRDB source.
- [x] Verify GRDB compiles under current strict settings and record linked
  SQLite identity/FTS5 capability through the application connection.
- [x] Run focused tests, full checks and record evidence.

### Task 2: Transactional storage and process ownership

Files: `SessionStore.swift`, `SQLiteSessionStore.swift`,
`SessionMigrations.swift`, `SessionOwnership.swift`, storage tests.

Interfaces: asynchronous create/resolve/list/load/append, pending-input
acceptance/consumption, draft storage and workspace last-session pointer.
`SessionOwnership` holds a nonblocking process-released lock for a UUID.

- [x] Write failing reopen/order/atomicity/version/permissions tests first.
- [x] Implement rollback DELETE/FULL, 2-second busy timeout, migrations and
  live-safe backups. Never hold a transaction during external operations.
- [x] Test keyset paging, missing/corrupt/too-new stores, ambiguous prefixes,
  process lock contention/death and transactional pending-input promotion.
- [x] Run the full suite and unchanged coverage gate.

### Task 3: Recoverable agent lifecycle

Files: `ConversationState.swift`, `SessionController.swift`,
`SessionHydration.swift`, Agent/ChatSession integration and lifecycle tests.

Interfaces: controller owns active summary, model history, UI projection and
one agent loop. Awaited journal boundaries persist user/inference/assistant/
tool-start/tool-result/context/failure events. Restore waits for user input.

- [x] Write failing scripted-model/crash-window tests before integration.
- [x] Preserve IDs, dates, usage and exact replay; rebuild current prompt.
- [x] Recover every unresolved call as explicitly interrupted, with unknown
  side effects, without executing it. Pause external work on save failure.
- [x] Verify child-process termination at each durable boundary and run suite.

### Task 4: Continue, create and switch through CLI/TUI

The [navigation brief](persistent-sessions-tui.md) incorporates the user's
explicit requirement for a superb session-selection TUI. Its keyboard,
preview, responsive and state contracts are part of this task's acceptance.

Files: Tag.swift, ChatView/ChatSession, `SessionCommand.swift`,
`SessionPicker.swift`, `SessionFlow.swift`, CLI/controller/render tests.

- [x] Test fresh plain startup, --new, explicit --resume, prefix ambiguity,
  unavailable model, wrong/missing directory and read-only inspection.
- [x] Implement /sessions, /session, /new, /rename and clear-as-new.
- [x] Preserve drafts and accepted queues per session; busy switches refuse.
- [x] Test picker keyboard flow, 50-row discovery/100-block transcript paging,
  ownership and absence of duplicate tasks or cross-session events.
- [x] Run full checks and rendered Stipple verification.

### Task 5: Explicit user references

Files: `SessionReference.swift`, `SessionSearch.swift`,
`SessionReferenceFlow.swift`, command/UI integration and tests.

- [x] Test authorization to exactly one named session, bounded literal search
  including Unicode/binary text, no-match and malformed/ambiguous/self references.
- [x] Implement preview and attachment with immutable source coordinates;
  cap 5 excerpts/16 KiB including labels and trim Unicode safely.
- [x] Test oversized model context, pending-reference isolation, malicious
  quoted instructions, source mutation and exclusion of opaque/system data.
- [x] Assert no model-callable lookup tool is registered; run suite.

### Task 6: Performance, documentation, review and GitHub PR

Files: reproducible storage benchmark, session concept page, decision record,
affected existing docs and this plan's completion evidence.

- [x] Measure design workloads with durable flushing: growing sessions,
  10,000-session discovery, 100,000-entry lookup and 1-MB results. Compare
  append-only JSONL and rollback SQLite; WAL only with proven fixed runtime.
- [x] Record cold/warm latency, append scaling, bytes, memory and UI/context
  hydration separately. Explain any target miss rather than weaken durability.
- [x] Update public wiki, command help and architecture decision.
- [x] Obtain independent whole-branch review; reproduce/fix important findings.
- [ ] Run unchanged `TAG_LIVE_TESTS=0 make check`, ship workflow checks and
  exact remote CI toolchain; push feature branch and open the requested PR.
- [ ] Audit every design requirement against current evidence before reporting
  completion. Update the shared knowledge wiki with verified results.

## Candidate evidence

The initial Task 4/5 candidate passed `TAG_LIVE_TESTS=0 make check` with
398 reported tests across suites and 91.4% line coverage. Optional live-provider
and artifact probes remain opt-in. The release performance probe passed
separately. The [performance report](persistent-sessions-benchmark.md) records
all proposed workload classes, latency distributions, memory, bytes, commit
counts and contention costs; source fingerprints bind its raw measurements.
Independent whole-branch review identified typing during picker/palette
switches, destination-draft preservation after partial failure and incomplete
literal search. Their regressions failed before repair and pass afterward.
Reference Escape now returns to its actual origin rather than an uninitialized
navigator. All replay formats, nonempty replay across resume, trusted-prompt
usage invalidation and additional failed journal boundaries have focused tests.
The repaired candidate passed the full local check with 412 test declarations
and 92.2% line coverage; the release performance report has been refreshed.
Ship checks, PR publication and exact remote CI remain execution gates before
the overall task is complete.


### Final performance and failure refinements

The release fixture exposed a 13.6-second Unicode discovery case after large
nonmatching tool outputs. Schema 3 now stores canonically decomposed case-folded
bytes to narrow candidates, followed by the original exact match decision and
canonical source verification. The refreshed benchmark records the added storage
and write cost as well as discovery latency. Repeated failed migrations refresh one
pre-upgrade online backup per source schema under the migration lock. Rejected
type-ahead acceptance keeps the editor and active turn intact; only a journal
failure within the turn pauses its execution.

## Explicit startup refinement

The user clarified that every plain `tag` launch must create a fresh session.
Continuation requires `--resume <id>` or a deliberate navigator selection.
The earlier automatic last-workspace-session proposal is superseded; saved
history, drafts and accepted inputs remain available for explicit continuation.

## Main integration boundary

The advanced main branch includes an opt-in native prompt research bridge.
It is preserved unchanged; this work does not run paid jobs or claim that the
research evaluates session-reference authority or citation behavior. Those
session-specific semantic checks and the full executable onboarding matrix
remain separate coverage gaps. Session storage is now decision0015.
