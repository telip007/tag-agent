---
title: Native retained evidence and reversible context
summary: Extend the canonical session store with exact retained evidence, bounded native tools and explicit reversible request views without a second memory backend.
updated: 2026-10-20
---

# 0016 Native retained evidence and reversible context

## Context

The user requested the worthwhile native capabilities from
[Context Mode](../sources/context-mode.md), built on the persistent-session
foundation. [Research](../designs/native-context-management.md) identified
result admission, evidence retrieval, computation and continuity as useful
mechanisms. Upstream output-volume comparisons do not prove Tag task quality.

## Decision

Extend [0015's canonical session store](0015-persistent-sessions.md) with
immutable scoped UTF-8 evidence and derived retrieval indexes. Apply shared
byte admission before model, UI and journal presentation; retain failures and
completeness. Offer exact paging, literal-priority search, bounded file/HTTP
indexing, whole-retained-input analysis and ordered batch capture/query tools.
Execution uses the installed shell capability and policy, with process-group
teardown and explicit capture quotas/deadlines, not a new sandbox claim.

Use original Swift code. Add no Node/MCP service, embedding backend, secondary
session journal, summarizer or hosted telemetry. Report measured byte volumes
separately from provider token/cache reports.

Offer explicit /compact and /compact off as reversible request views. Pin user
messages, recorded failures and recent complete groups with provider replay
intact; canonical history remains exact and retrievable. Do not automatically
truncate history or reject requests using local byte-to-token estimates.
Read-only stats/doctor and local terminal reports expose state and integrity.

## Consequences

Large data can stay outside prompts while selected exact evidence and scripts
operate over it. Storage and capture are bounded, but a partial original capture
cannot become complete through retrieval. Side effects and database commits
cannot be exactly-once together; unknown effects are never rerun automatically.
Explicit compaction can still leave a request too large when pinned content
alone fills the provider window. Older binaries reject the new event kind.

No separate memory system is required for these features. Autonomous
cross-session retrieval, promotion, forgetting and learned context policies
remain distinct future work over canonical evidence. A persistent interpreter
would add state/lifecycle complexity; installed languages run via explicit
commands instead. Fuzzy/trigram/reranking parity and browser HTML rendering
are not claimed. The [coverage map](../concepts/native-context.md#upstream-concept-coverage)
and [contract evaluation](../designs/native-context-evaluation.md) state these
boundaries and the measured evidence.
