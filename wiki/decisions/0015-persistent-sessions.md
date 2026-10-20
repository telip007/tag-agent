---
title: Transactional local sessions
summary: Persist lossless versioned session events in private SQLite storage, with explicit references and autonomous memory retrieval kept separate.
updated: 2026-10-20
---

# 0015 Transactional local sessions

## Context

The user approved implementing [persistent sessions](../designs/persistent-sessions.md):
continuation, switching and user-directed references. In-memory UI blocks alone
lose provider replay, tool IDs and exact model input. Automatic session discovery
belongs to later memory/dreaming work.

## Decision

Use a SessionKit library over GRDB 7.11.1 and system SQLite. Keep an explicit
versioned semantic event log with transactional metadata projections, pending
inputs and drafts. Keep ModelKit independent of SQL and TagKit responsible for
the UI and one active agent loop. Reference attachments copy bounded readable
excerpts with immutable source coordinates; no autonomous lookup tools.

Start with DELETE journaling, FULL synchronization, fullfsync on macOS and a
two-second busy timeout. WAL requires proof of a fixed linked engine and a
deliberate packaging/migration decision, as described in the design's sources.
Preserve all compiler, lint and coverage checks. Use owner-only storage under
the protected config tree, with process-released session ownership locks.

## Consequences

Incremental entries avoid whole-history rewrites. Transactions make acceptance,
input promotion and saved metadata atomic. A crash cannot imply exactly-once
filesystem effects: unresolved tools must be labeled interrupted and never
rerun automatically. Restoring a session waits for the user.

JSONL remains a benchmark/export alternative, not a second canonical store.
No claim of best performance is made before the specified measurements.
Implementation and validation progress are recorded in
[session storage](../concepts/session-storage.md) and the execution plan.

## Review refinements

Literal lookup includes Unicode, word fragments, punctuation and binary tool
output; token-only FTS cannot guarantee that contract. Schema 3 removes its
unused maintenance and rebuilds derived text from canonical records, after an
online backup of existing stores. Discovery uses indexed per-session existence
checks so metadata filters and the page limit bound ordinary matching queries.
A canonically decomposed case-folded byte projection supplies cheap candidates
before original-text verification; this avoids repeatedly running Unicode search
over large nonmatching tool output. It costs another derived copy of readable
text. Migration retries atomically refresh one backup per source schema, keeping
the latest pre-upgrade data without unbounded backup growth.

Failed acceptance of type-ahead input preserves the draft and leaves the active
turn running. Journal failures within that turn still stop before further external
work.

The user chose provider-authoritative context limits: preserve the complete
request and show explicit recovery when the provider rejects it. Byte-count
heuristics must not prevent valid continuation. No automatic truncation or
compaction is introduced.

The user clarified startup separately: every plain `tag` launch starts a new
session. `--new` remains an explicit equivalent; `--resume <id>` or a deliberate
navigator selection continues saved work. Last-opened metadata does not authorize
automatic continuation. Reopening must preserve old history, drafts and pending
input without installing them into the fresh conversation.
