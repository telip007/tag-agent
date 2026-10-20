---
title: Native context management implementation plan
summary: Execution ledger for native output storage, retrieval, indexing, analysis, batching, compaction and diagnostics on the persistent session foundation.
updated: 2026-10-20
---

# Native context management implementation plan

Goal: implement worthwhile Context Mode mechanisms natively, validate them,
and open a PR. The user's implementation request supersedes the earlier
research-only status. No gstack skills are used.

Architecture: reuse SessionKit's durable SQLite journal and session ownership;
add immutable output artifacts and derived search in the same database.
TagKit admits bounded output and exposes native retrieval/analysis tools.
Canonical journal entries stay intact while a request view can compact old
observations. No cross-session autonomous search is introduced.

Spec: [research and architecture](native-context-management.md).
Stack: Swift, existing GRDB 7.11.1, swift-subprocess 1.0.2, Foundation.
Dependency base: persistent sessions PR #2, committed `950a8aa` initially;
updated to published `f7cc679` for feature verification. PR #2 then landed as
`48615e2` on main with the exact same tree; the feature branch incorporates
that published main history and PR #3 targets main.
Execution: inline, test-first, independent whole-branch review before PR.

## Constraints and review focus

- Keep macOS 15, Swift tools 6.2, strict compiler/lint settings and 80% coverage.
- New original code; no upstream vendoring, installation or external services.
- Exact evidence and incomplete-capture status survive display reduction.
- Scoped artifact IDs cannot read another session or arbitrary storage paths.
- Retrieval output is bounded and never recursively re-archived.
- Unknown side effects after storage/crash failures are never rerun automatically.
- Complete assistant/tool groups and opaque replay survive compaction/resume.
- Byte estimates never masquerade as exact provider token usage or monetary savings.

## Tasks and completion ledger

### 1. Durable output evidence

Files: SessionKit OutputRecords, OutputStore, OutputChunks and a migration;
Tests/SessionKitTests/OutputStoreTests.swift. Interfaces: saveOutput scoped by
session UUID, readOutput byte pagination, immutable OutputReference metadata.

- [x] RED: real database reopen, exact Unicode/NUL recovery, isolation,
  invalid range, quota rejection and no partial write.
- [x] GREEN: same-store migration, bounded immutable blobs, content hashes,
  provenance, completeness and serialized off-main-actor writes.
- [x] Verify focused tests and existing migration/recovery tests; commit.

### 2. Search and diagnostics

Files: SessionKit OutputSearch, OutputStatistics; tests for known tail errors,
code identifiers, literal special characters, no-match and scoped pagination.

- [x] RED: exact citations and source ranges, search after reopen, bounded
  aggregate results, non-FTS fallback and short identifier behavior.
- [x] GREEN: rebuildable FTS5 BM25 with safe literal queries and exact fallback;
  stored/admitted bytes and capture counts reported separately.
- [x] Verify deterministic long-output recall fixtures; commit.

### 3. Bounded capture and admission

Files: TagKit ToolOutcome, ToolAdmission, ProcessRunner, FileTools, ShellTools,
Agent execution seam, SessionController wiring and relevant tests.

- [x] RED: small results unchanged; >1 MB output retains final failure;
  status/signal/capture limits; file and list budgets; multi-call output budgets.
- [x] GREEN: streaming capture with quotas, preserve search overflow,
  archive before bounded model/UI emission, explicit structured outcomes.
- [x] Verify storage failure after a side effect never dispatches again;
  existing session and tool-loop tests; commit.

### Task 4: Native index and retrieval tools

Files: TagKit ContextTools, ContextIndexing, ContextFetch; injectable URLSession
transport at the network boundary for deterministic tests.

- [x] RED: read_output exact ranges, search_output bounded matches,
  index_file protected paths/symlinks, index URL text with source metadata,
  nontext/oversize/fetch failures, no cross-session access.
- [x] GREEN: session-bound tools, source hashes, safe pagination,
  timeout/response limits and explicit untrusted source labeling.
- [x] Verify tools through scripted Agent calls and real local fixtures; commit.

### Task 5: Compute and batch acquisition

Files: TagKit ContextAnalysis, ContextBatch and tool tests.

- [x] RED: exact aggregate over all artifact bytes; script failure remains
  visible; batch queries stay batch-scoped; ordered writes and per-command
  status; cancellation and time/output quotas.
- [x] GREEN: execute analysis using an artifact as subprocess input without
  exposing internal credential paths; batch commands then retrieve their
  indexed outputs. Reuse existing bash authority, never claim an OS sandbox.
- [x] Verify full-data aggregate versus sparse retrieval; commit.

### Task 6: Working context and continuity

Files: TagKit ContextProjection, ConversationState, AgentJournal integration;
SessionKit versioned context projection records if persistence requires them.

- [x] RED: long histories, model changes, pending tools, preserved user
  corrections, recent errors, signed replay and interrupted resume.
- [x] GREEN: budget-pressure observation externalization into a derived view,
  bounded evidence-linked recovery state, immutable canonical journal,
  optional explicit compaction controls. Do not rewrite prefixes each turn.
- [x] Verify deterministic request payloads across adapters and reopen; commit.

### Task 7: Product surfaces, evaluation and PR

- [x] Add native context stats/diagnostics and local help; actual TUI tests.
- [x] Map all upstream tools/concepts to shipped behavior or justified exclusion:
  execute/file analysis, batch, index/search/fetch, stats/doctor, continuity,
  routing and data-flow guidance; omit plugin upgrade/install and hosted analytics.
- [x] Run deterministic quality/recall/whole-input/byte-admission comparisons;
  no paid provider runs are required for the implementation contract.
- [x] Update concept pages, decision record, README and research status;
  shared wiki maintenance with conflict-safe helper.
- [x] Full make check, exact remote CI, independent review, scoped fixes,
  commit/push feature branch and open PR (stacked if #2 remains open).

## Rulings and progress

- Integrated committed persistent-session foundation in the existing managed
  worktree; retained both branches' wiki entries. Other checkouts stay untouched.
- The full goal remains active through every task; task 1 is foundational
  progress, not a substitute for the remaining native features.


## Feature completion evidence

[PR #3](https://github.com/telip007/tag-agent/pull/3) is open against main.
The session foundation landed as `48615e2`; its tree is identical to the
previously integrated `f7cc679`, and the native source delta was preserved
byte-for-byte when joining that published history. The SDK and inherited
prompt-evaluation archive are unchanged by this feature.

Feature revision `a8b47d3f5663675df1383d1ccdc97e9b32ec267f` passed
[exact CI 39469218910](https://github.com/telip007/tag-agent/actions/runs/39469218910):
514 tests, 91.7% coverage and Swift 6.3.3, with all strict/80% checks unchanged.
Local full gates match those counts; the six deterministic native fixtures
and their limits are in the [evaluation](native-context-evaluation.md).
The capability map and justified exclusions are in
[native context](../concepts/native-context.md#upstream-concept-coverage).

A fresh independent whole-branch review found two important issues and no
critical or minor findings. Post-effect spool I/O now preserves fail-stop
recovery, and doctor checks the exact derived chunk layout including overlap;
both regressions were observed failing before the fixes. Remote integration
then exposed transport-timeout normalization and fixture observation/debug
setting issues; these were diagnosed and verified without relaxing production
limits, lint, coverage or the fetch test's elapsed bound.

All implementation tasks are complete for the feature PR. The documentation
completion record goes through the normal publication gates as well. Merge,
release and runtime installation remain separate maintainer actions.
