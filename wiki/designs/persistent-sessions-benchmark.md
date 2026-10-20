---
title: Persistent session performance
summary: Release measurements of durable SQLite and JSONL, indexed discovery, bounded UI restoration and local input readiness.
updated: 2026-10-20
---

# Persistent session performance

The candidate meets the proposed warm p95 budgets in this generated-data run.
SQLite provides atomic history, metadata and search; these measurements do not
establish a universally fastest backend. Bare JSONL writes fewer bytes and is
faster for 1 MiB appends, while it omits the indexed consistency guarantees.

Reproduce on macOS with:

```sh
python3 Scripts/session-benchmark.py --output benchmark.json
```

The script builds release tests and SessionProbe, uses private marked temporary
fixtures, performs no provider calls and removes generated stores afterward.
See the [raw measurements](../../Benchmarks/session-storage-2026-10-20.json),
[harness](../../Scripts/session-benchmark.py),
[UI measurements](../../Tests/TagKitTests/SessionPerformanceTests.swift) and
[approved budgets](persistent-sessions.md#proposed-measurement-budgets).

## Method and scope

The fixture has exactly 10,000 sessions and 100,000 searchable entries, including
histories of 1,000 and 10,000 entries with approximately 4 KiB text. Readable
fixtures include multiple lines, Unicode and tabs. Setup uses a
bulk transaction and is excluded from timings. Measured writes use the real
store API, with DELETE/FULL/fullfsync; JSONL calls fsync and F_FULLFSYNC before
acknowledgment. One append is one acknowledged commit. JSONL preserves versioned
events and coordinates, without metadata or text indexes. It is a comparison
of storage costs, not a substitute implementation of all session features.

Each storage phase starts a new process/connection. Its first-access sample is
reported separately; operating-system page cache is uncontrolled. This is not a
physical cold-cache or power-on test. Warm p50 is the median and p95 uses nearest
rank after excluding the first sample. Appends and indexed reads use 128 samples;
1 MiB appends and full-history loads use 32; absent and emoji discovery use
16 samples each. UI component timings use 32 samples
in one test process; local input readiness uses eight trials per history size.

The linked SQLite version is `3.51.0`, with FTS5 available. Its source ID is:

```text
2025-06-12 13:14:41 f0ca7bba1c5e232e5d279fad6338121ab55af0c8c68c84cdfb18ba5114dcaapl
```

Vendor WAL-fix status remains unknown. WAL is neither adopted nor benchmarked.
The raw report records a SHA-256 fingerprint of package, Swift sources/tests
and benchmark-script inputs.

The measurements precede the final quit-test synchronization refinement.
Storage/UI implementation, dependencies and executed benchmark workloads are
unchanged; the raw fingerprint identifies the exact measured test snapshot.

## Storage latency

All values below are milliseconds. The 4 KiB and 1 MiB labels describe content
size; version envelopes, coordinates and indexes add storage overhead. Full-load
phases follow the append phases, so those histories also contain 128 new 4 KiB
entries and 32 new 1 MiB results.

| Initial history | Operation | First access | Warm p50 | Warm p95 |
| --- | --- | ---: | ---: | ---: |
| 1000 | sqlite-4k | 6.54 | 2.16 | 3.33 |
| 1000 | jsonl-4k | 5.06 | 4.57 | 8.16 |
| 1000 | sqlite-1m | 16.50 | 11.24 | 13.86 |
| 1000 | jsonl-1m | 7.76 | 7.02 | 9.04 |
| 1000 | load | 82.96 | 71.22 | 74.13 |
| 1000 | jsonl-load | 207.20 | 204.36 | 206.12 |
| 10000 | sqlite-4k | 8.11 | 2.36 | 3.40 |
| 10000 | jsonl-4k | 4.68 | 4.79 | 8.10 |
| 10000 | sqlite-1m | 14.78 | 10.59 | 13.52 |
| 10000 | jsonl-1m | 5.88 | 7.05 | 8.08 |
| 10000 | load | 246.39 | 224.31 | 227.65 |
| 10000 | jsonl-load | 498.13 | 485.17 | 489.71 |
| all sessions | list | 0.94 | 0.61 | 0.71 |
| all sessions | discover | 107.51 | 54.06 | 55.16 |
| all sessions | discover-miss | 149.39 | 152.84 | 160.13 |
| all sessions | discover-unicode | 53.18 | 52.14 | 53.90 |
| all sessions | search | 1.15 | 0.24 | 0.35 |

`list` reads a 50-row metadata page. `discover` matches a literal word across
all sessions; `discover-miss` returns no match, and `discover-unicode` matches an
emoji after the large output appends. `search` retrieves at most five excerpts from one named session
while the global index contains 100,000 entries. Literal verification and
canonical excerpt validation remain enabled.

## UI and usable input

The component timings use the original 1,000/10,000-entry fixtures before large
results are appended. Only 100 observed rows are created; all historical model
messages remain available. Visible-row restore/render excludes full-history
loading and projection, which are listed separately.

| Entries | Component | First trial | Warm p50 | Warm p95 |
| --- | --- | ---: | ---: | ---: |
| 1000 | Full history load/decode | 50.40 | 17.41 | 18.67 |
| 1000 | Model-message restoration | 0.77 | 0.03 | 0.11 |
| 1000 | Value transcript projection | 0.31 | 0.04 | 0.05 |
| 1000 | 100 observed rows | 0.18 | 0.04 | 0.04 |
| 1000 | Transcript render | 79.10 | 70.68 | 73.07 |
| 1000 | Controller open to editable TUI | 186.50 | 160.60 | 164.21 |
| 10000 | Full history load/decode | 592.93 | 171.40 | 287.49 |
| 10000 | Model-message restoration | 0.64 | 0.38 | 1.14 |
| 10000 | Value transcript projection | 0.48 | 0.45 | 0.95 |
| 10000 | 100 observed rows | 0.04 | 0.04 | 0.04 |
| 10000 | Transcript render | 71.51 | 71.11 | 83.95 |
| 10000 | Controller open to editable TUI | 328.97 | 324.78 | 351.45 |

Usable-input trials open the real controller and native Stipple runtime, await
its input boundary and type a local draft. They include recovery, history
loading, trusted-context revision and rendering. A
consistent separate backup isolates their draft/context writes from the storage
workloads. Provider catalogues, replies and the environment probe are fixtures;
context fit is provider-authoritative and no local byte gate is measured. Database connection setup,
network catalogue/sign-in latency and real environment probing are excluded.
These are local restoration measurements, not complete network-backed CLI launch
times or a claim that a real provider accepts every generated history.

## Memory, bytes and concurrency

| Initial history | Operation | Peak storage-process RSS (MiB) | OS bytes written (MiB) | Acknowledged commits |
| --- | --- | ---: | ---: | ---: |
| 1000 | sqlite-4k | 13.4 | 29.80 | 128 |
| 1000 | jsonl-4k | 13.1 | 2.54 | 128 |
| 1000 | sqlite-1m | 35.1 | 103.17 | 32 |
| 1000 | jsonl-1m | 17.1 | 32.50 | 32 |
| 1000 | load | 142.5 | 0.00 | 0 |
| 1000 | jsonl-load | 115.4 | 0.00 | 0 |
| 10000 | sqlite-4k | 13.4 | 30.57 | 128 |
| 10000 | jsonl-4k | 13.1 | 2.52 | 128 |
| 10000 | sqlite-1m | 35.1 | 103.52 | 32 |
| 10000 | jsonl-1m | 18.1 | 32.52 | 32 |
| 10000 | load | 250.2 | 0.00 | 0 |
| 10000 | jsonl-load | 212.2 | 0.00 | 0 |

The seeded database occupies 254.85 MiB; secondary B-tree
indexes account for 20.09 MiB, measured through dbstat. No FTS
auxiliary tables are maintained. Canonical payloads, readable text and folded
candidate bytes intentionally retain separate representations. Folded candidates
avoid expensive original-text Unicode scans over nonmatching large output;
the original matcher remains authoritative. The complete UI test process peaks
at 549.8 MiB physical footprint across both sizes, repeated render/startup
trials and backup work. That lifetime maximum is not a separate peak attributable
to each component or size. Storage RSS comes from time -l; UI footprint comes
from proc_pid_rusage v4 in the Python coordinator. Swift strict memory-safety
checks remain unchanged.

OS-accounted write deltas include filesystem/journal traffic and a small result
report; they are not physical NAND writes. SQLite maintains several structures
and a rollback journal per commit. Its larger write volume is a measured cost;
these results do not justify weakening flush durability or introducing two
authoritative stores. Appends do not rewrite or encode pre-existing history.
The larger history shows no append-growth penalty here; differing timings
between fixture positions are not evidence that longer histories are faster.

Two independently launched writer processes append to different sessions while
a third process repeatedly reads metadata pages:

| Concurrent operation | First access | Warm p50 | Warm p95 |
| --- | ---: | ---: | ---: |
| sqlite-4k (1) | 361.55 | 2.68 | 3.26 |
| sqlite-4k (2) | 7.43 | 2.52 | 3.08 |
| list (3) | 765.40 | 0.63 | 0.96 |

A contended first write waits 361.55 ms. DELETE serializes writers; warm
percentiles do not eliminate this tail. The configured busy timeout remains two
seconds. This experiment and the process tests establish exercised contention,
not scheduling fairness or unlimited writer throughput.

## Budget assessment

Warm 4 KiB appends stay below 20 ms; 1 MiB appends below 100 ms; metadata pages
below 50 ms; bounded scoped reference queries below 100 ms. Paired observed-row
restoration plus rendering stays below the 100 ms warm p95 budget at both sizes.
Full-history loading and actual input readiness are deliberately reported
separately. The full-content discovery query is slower than a metadata page,
and its absent-query warm p95 of 160.13 ms remains slower than its matching
query. First-access contention and memory/write amplification remain visible costs.

Keep the correctness-first SQLite design for its atomicity, bounded discovery
and observed latency. Consider WAL or indexing changes only after engine
compatibility and a specific measured bottleneck justify them.
