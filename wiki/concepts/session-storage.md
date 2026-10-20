---
title: Session storage
summary: Durable local conversations, provider-authoritative context limits, keyboard session navigation and explicit bounded references.
updated: 2026-10-20
---

# Session storage

The implementation follows the [session design](../designs/persistent-sessions.md)
and [execution plan](../designs/persistent-sessions-plan.md). Durable boundaries,
recovery, CLI/navigation integration and release performance checks have local
verification. Final ship checks, PR publication and exact remote CI remain
acceptance gates.

`Sources/SessionKit` depends on ModelKit and the pinned GRDB 7.11.1 package.
ModelKit owns an explicit role-tagged `Message` encoding; SessionKit wraps
semantic events in an envelope with format version 1. Unknown roles, versions
and corrupt payloads throw rather than silently producing empty history.

`SQLiteSessionStore` uses a `DatabaseQueue`, system SQLite, DELETE journaling,
FULL synchronization, macOS fullfsync and a two-second busy timeout. Opening
and backups run away from the caller's actor; ordinary reads/writes await
GRDB's database queue. No external operation belongs inside a SQL transaction.
WAL remains an explicit later compatibility/performance decision; an existing
WAL store is refused instead of silently changing journal mode.

Sessions have stable local/provider IDs and workspace identities. A new session
uses its local UUID as the provider ID; explicit resume restores it for OpenCode
Go routing headers, Responses cache keys and OpenRouter session IDs. New starts
get new IDs, without implying that a provider will serve a cache hit. Entries
append incrementally with per-session sequence allocation. Metadata, titles,
usage and dates update in the same transaction. Pending inputs have stable
IDs and promote into user entries atomically with deletion from the queue.
Drafts and last-opened workspace pointers are separate from model history.

Database, locks and backups are owner-only. `SessionOwnership` uses a
nonblocking kernel lock for the lifetime of an active session. Close and switch
explicitly release ownership after the real agent task exits; a retained Swift
reference cannot delay kernel unlock. Release is synchronized and idempotent.
Schema setup
is serialized by another process-held lock; a future schema is preserved and
rejected. Schema 2 adds a readable-text projection. Schema 3 removes unused
word-token FTS and rebuilds the projection from canonical events using
byte-preserving bindings, including embedded NUL in tool output. It also stores
a canonically decomposed case-folded byte projection. SQLite rejects absent
candidates before Foundation checks the original text, keeping large Unicode
searches responsive without changing literal-match semantics.
Recognized schema-1/2 stores receive a private online backup before upgrade.
Under the migration lock, retries atomically refresh one backup per source
schema instead of accumulating full copies after a failed upgrade. The separate
explicit backup API refuses to overwrite an existing destination. Initial schema creation has no historical data
to back up; subsequent schema upgrades must take an online backup first.
Backup destinations currently use SQLite/GRDB default flushing rather than an
explicit macOS fullfsync policy. Online consistency is verified; backup survival
under physical power loss has not been qualified. Canonical store commits retain
FULL/fullfsync.

## Current verification

The integrated local checkpoint passed `TAG_LIVE_TESTS=0 make check`: 425 test declarations
across TagKit (269), SessionKit (40) and ModelKit (116), with 91.7% coverage over
9,909 source lines and unchanged strict checks. Optional live/provider and artifact probes are
skipped in that command; the release performance probe passed separately.
Real-database and codec tests cover reopen, exact replay, nil/empty,
ordered concurrent appends, rollback on injected append failure, stable usage
and identity, metadata paging, drafts, process-style file locks, private
permissions, too-new/corrupt payloads and online backup/reopen. The [release benchmark report](../designs/persistent-sessions-benchmark.md) records
latency, memory, write amplification and input readiness. Earlier candidates
received native and outside reviews; the latest correction received a native
review, while the additional outside review was unavailable because its provider
quota was exhausted. The PR records exact remote CI evidence separately from
this local result. Generated-fixture-only
tests use a `SessionProbe` child process: SIGKILL at 11
agent boundaries, kernel ownership release, concurrent migration/readers/writers,
and rollback of an uncommitted transaction with a live private journal. These
checks use no provider or credentials and isolate child coverage profiles.
Managed database, lock and backup paths reject symlinks and special files.
Rejected input acceptance leaves the unsaved draft and active turn intact.
An injected continuation-pointer failure pauses switching until retry saves the
pointer; no message is accepted in the failed intermediate state.

The recovery layer fills every unresolved tool call with an explicit
interrupted result, preserving committed results and distinguishing unknown
effects from tools never started. Recovery is transactional and idempotent.
The agent's optional journal waits for saves before inference and tool effects;
a failed save stops its loop before subsequent external work. The controller
provides visible pause/retry and one foreground task.

Transcript hydration retains raw user text, complete replies/reasoning, tool
durations and edit summaries. Only the newest 100 observed rows are created
initially. Older value rows page in with stable IDs; open streaming row indices
move with a prepend so a delta cannot update an unrelated historical block.
Completed reasoning with unknown duration is distinct from active streaming.

## Navigation and explicit references

Plain `tag` always creates a new session in the canonical current workspace;
`--new` is an explicit equivalent. `--resume <id>` opens a saved session by full
ID or unique prefix, and the navigator also permits explicit continuation.
Closing and reopening Tag never implicitly resumes a conversation. Worktrees
remain distinct. Opening waits for input. Foreign workspaces and sessions
owned by another process open read-only, without recovery writes or dispatch.
A saved model that is unavailable requires an explicit `/model` choice. Model
choices save at a ready boundary and on clean exit even if no inference follows;
an active request keeps its own recorded model until that boundary.

Ctrl-O or `/sessions` opens the keyboard navigator. Search covers titles and
readable conversation content, with current-workspace and all-workspaces scope.
Rows lead with titles and cached excerpts; wide terminals place a conversation
preview beside the list, and narrow terminals place it below. Arrows/Ctrl-J/K
move, page keys move a page, Enter opens, Escape returns to the unchanged draft,
Tab changes scope, Ctrl-N creates, Ctrl-R renames and Ctrl-L previews a reference.
Enter and mouse actions capture the intended stable session ID before any
async work; rename retains its source even if selection moves. Ctrl-U clears
the title and Ctrl-W deletes a word. Session, new-session and reference actions
are also available in the command palette.
The database pages 50 session rows; the transcript initially observes 100 rows.

| Command | Behavior |
| --- | --- |
| `/session <id>` | Open a unique session ID or prefix |
| `/new`, `/clear` | Create a new session, retaining the old history |
| `/rename <title>` | Rename the writable current session |
| `/reference [id [words]]` | Choose a source or preview literal matches in exactly that source |
| `/unreference` | Remove unsent reference attachments |
| `/pending` | Review the next restored accepted input; Enter explicitly sends it |
| `/retry` | Reload/recover after fixing a save failure, without automatic dispatch |

Reference search excludes system prompts, date annotations, reasoning, opaque
replay and failure internals. Discovery and references use case-insensitive
literal substring matching, including Unicode, internal word fragments,
punctuation and emoji. ASCII text takes a native SQLite fast path; Unicode
matching returns offsets in the original text's Unicode scalars. Word-token
FTS cannot provide a complete substring candidate set, so searches use the
readable projection rather than excluding valid matches. Discovery checks
indexed per-session entries in recency order and stops at its 50-row page;
workspace filtering happens first. Folded bytes narrow candidates; original-text
matching remains authoritative, and selected folded/text projections are verified
against canonical events before quoting. Schema 3 stops maintaining unused FTS.
Results select the
five newest matching entries and display them in conversation order; they are
not relevance-ranked. Empty queries select the latest completed exchange.
Matching excerpts are centered near the match, so a word deep in a large tool
result is not replaced by its unrelated first lines. Selected canonical payloads
pass version decoding, readable-role and exact excerpt validation before their
searchable projections are quoted. Citation timestamps come from canonical
entries. A corrupt derived index cannot invent source text or expose a prompt
event as a readable quote. A
preview must be
confirmed before attachment; arrows, page keys and Home/End scroll that preview.
Sent and restored attachments remain expandable in the transcript. At most five
copied excerpts fit 16 KiB including
JSON quoting and source labels. The destination saves exact copied content,
UUID/title/sequence/role/time citations and exact rendered model input. Source
renames cannot change it. A trusted prompt rule treats excerpts as historical
data without inherited permissions. No lookup tool is registered for the model.

Typing during a save acknowledgment remains as the next editable draft; the
acknowledgment consumes only the submitted text. WorkspaceEditor also consumes
UI commands before saving the source draft, preserves typing during rename, and
buffers typing during a slash-command switch for the destination only. Native Stipple keyboard-runtime
tests cover opening/closing the picker, palette discovery, new-session draft
preservation and a deliberately blocked save.

Pending-input review preserves its original identity after edits. Accepting a
draft and clearing its saved editor copy happen in one transaction. Restored
queues are separate from live dispatch; switching and clean exit save drafts
and await the previous foreground task before releasing its ownership lock.

## Context limits

The provider decides whether the complete request fits its model window. A byte
count is not a token count, so Tag does not reject a valid continuation using a
local byte heuristic. Opening a long session still waits for user input without
calling the model. Model/prompt changes discard stale latest-usage/cache figures
while retaining historical messages, replay data and accumulated cost.

No history is silently truncated. Accepted messages, references and tool results
remain durable when a provider rejects a request. The failure offers retry,
`/model` for a larger model and `/new`; references remain capped separately at
five excerpts/16 KiB. A failed request returns to the input boundary rather than
stranding the session behind a local estimate. Tests send full restored history,
refresh the trusted prompt, inject a provider context rejection and assert exact
saved input/excerpts and the visible recovery choices.

Explicit `/compact` creates a reversible shorter request view while retaining
the complete canonical journal and transcript. It pins all user input, failed
and recent complete groups, with exact scoped history retrieval for older
records. `/compact off` restores the original view. This is an explicit user
choice, not an automatic context-window gate or a generated summary; see
[native context management](native-context.md).

## Gotchas

- `MemberImportVisibility` requires a direct ModelKit import in a file reading
  `Usage.cost` or `totalTokens`, even if another SessionKit file publicly imports
  ModelKit. Keep checks strict rather than weakening import visibility.
- FTS5 capability is probed through the actual application connection using a
  temporary virtual table, not inferred from a separate executable's version.
- Restore UI, model history and external effects are different concerns. The
  lifecycle layer must never rerun a tool solely to restore a
  missing result.
