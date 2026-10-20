---
title: Provider-aware prompt caching
summary: Use native automatic caching and explicit opt-in boundaries where required, with observable provider-reported cache metrics and default retention.
updated: 2026-10-20
---

# 0013: Provider-aware prompt caching

## Context

The request is to implement proper prompt caching for all providers.
Session routing and some Anthropic markers already existed, but OpenRouter
opt-in caching and visible cache usage were missing. Anthropic's streaming
usage fields also need independent merging to avoid undercounting context.
See [prompt caching](../concepts/prompt-caching.md) for official sources.

## Decision

Use each format's native automatic caching; add explicit content boundaries
where opt-in is necessary, including unresolved OpenRouter router targets. Preserve the current and previous Anthropic user
boundaries within the four-marker limit. Keep session IDs stable and request
serialization deterministic. Surface optional read/write counts from every
adapter; distinguish missing metrics from reported zeros. Keep default TTLs
and provider-reported cost. These are implementation choices for the caching
request, not a claim of measured savings.

## Consequences

The full conversation and reasoning remain available to every model call.
No local answer cache, cache-object service or extra management requests are
needed. Model-specific minimums and server expiry still apply. Fixture tests
verify encoding, accounting and presentation; live hits are not guaranteed.
Router-selected Gemini models can incur explicit-cache storage charges; fixed
Gemini model slugs stay implicit. Longer retention and automatic monetary-savings estimates need separate
pricing and capability work.
