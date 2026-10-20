---
title: Prompt caching implementation
summary: Provider-aware cache requests, stable history boundaries and observable cache usage across all ModelKit formats.
updated: 2026-10-20
---

# Prompt caching implementation

Goal: implement proper prompt caching for OpenRouter, ChatGPT plan/Codex,
and all four OpenCode Go wire formats, without changing the conversation
or model output. See [prompt caching](../concepts/prompt-caching.md).

## Design

Keep the append-only history, stable tool order, session UUID and verbatim
reasoning replay. Use automatic caching for Responses, Chat Completions and
Gemini; keep the Responses session cache key and Go session header.
OpenRouter gets explicit ephemeral content boundaries for opt-in providers
(including Alibaba), plus its top-level automatic Anthropic control.
Anthropic keeps system/tools boundaries and the last two user-turn boundaries
so a large new turn cannot hide the prior cache entry outside the lookback
window. Never mark thinking/signature blocks or exceed four breakpoints.
Use default retention; do not assume an arbitrary gateway supports extended
retention or native Gemini cache-object APIs.

Normalize reported cache reads/writes as optional counts in Usage. Input
counts include cached tokens exactly once. Anthropic's independently updated
usage fields must be merged before totaling; other APIs already include cache
reads in input totals. Show the latest completed reply's cache counts in the status panel,
clear them on reset and when a reply omits usage. Retain provider-reported
cost; never estimate savings from incomplete pricing.

## Implementation plan

- [x] Add failing request tests for OpenRouter opt-in controls and Anthropic
  previous-turn boundaries, including large tool batches and signed replay.
  Implement adapter changes; run focused tests.
- [x] Add failing usage tests for all five wire formats, including absent,
  zero and partially updated Anthropic counters. Extend Usage and decoders;
  run focused tests.
- [x] Add failing agent/status tests for cache display and reset/unknown
  handling. Carry the latest counts to the existing sidebar and status text.
- [x] Update concepts/source notes, add a decision record, run `make check`,
  inspect the complete diff and preserve verified results in the shared wiki.

## Verification boundary

Fixture tests prove request encoding, decoding and UI state propagation.
They cannot prove a remote cache hit: model minimums, TTLs, routing and
provider availability still govern that. Paid live requests are not required
for this implementation. No SDK changes or live activation are planned.

## Review refinement

OpenRouter's selectable auto/pareto routers can resolve to Alibaba. They
therefore require explicit content markers too; relying on the unresolved
model slug's family misses caching entirely on that route. Router slugs use
markers by default, accepting the selected provider's explicit-cache pricing
(including Gemini storage when a router chooses Google). Fixed Gemini model
slugs continue to use implicit caching. This is an implementation choice to
cover opt-in providers through routers without restricting model selection.

## Verified result

Before the integration review repair below, `TAG_LIVE_TESTS=0 make check`
passed on 2026-10-20: 304 tests across both
test bundles, 91.5% line coverage against the unchanged 80% gate, wiki lint,
formatting, SwiftLint and build. A separate read-only code review found the
router opt-in gap; its fix was rechecked with no further material findings.
Regression tests were observed failing before request/accounting/display
changes. The sidebar cache text is also checked through Stipple rendering.
Live provider cache hits and monetary savings were not measured.

## Integration review repair

Before direct landing, integrated the newer Responses shared-stream refactor
from main. It already uses deterministic encoding, so the old adapter-specific
encoder edit is unnecessary. Adversarial review then reproduced stale sidebar
counts during tool loops and model switches. `.metrics(StatusLine)` publishes
current snapshots before inference and after every reply, without the
ready-for-input event's activity/tray resets. Tests observed missing, zero and
changed cache counts failing before this repair, and cover tray continuity.
