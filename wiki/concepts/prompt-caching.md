---
title: Prompt caching
summary: What Tag does about OpenRouter prompt caching today, what it leaves unused, and the steps to use all of it.
updated: 2026-10-18
---

# Prompt caching

Status on 2026-10-18: **nothing explicit.**
[`OpenRouterChatModel.reply`](../../Sources/ModelKit/Providers/OpenRouterChatModel.swift) sends only
`messages`, `model`, `tools` and `toolChoice`. Source:
[OpenRouter prompt caching](../sources/openrouter-prompt-caching.md).

## What works already, and what doesn't

| Feature | Used? | Effect |
| --- | --- | --- |
| Automatic caching (DeepSeek, OpenAI, Gemini, Grok, Moonshot) | Implicitly | DeepSeek, the default model, reads cached tokens at 0.1× the input price. |
| Append-only history | Yes | `Agent` only appends to `conversation`, the tool list has a fixed order, and reasoning fields are sent back unchanged, so the cached prefix stays valid. The most important part, already right. |
| Sticky provider routing | Partly | Without `session_id` it starts only after the first cache hit, keyed on a hash of the first system message and the first non-system message. Since [0009](../decisions/0009-system-prompt.md) the first system message is Tag's system prompt, identical for every request in a session. Until the first hit, requests may go to other providers and miss. |
| `session_id` | No | Sticky from the first request; groups the session on OpenRouter's Logs → Sessions page. |
| Top-level `cache_control` | No | Anthropic (and Alibaba) don't cache without it. Claude models get no caching today. |
| `cached_tokens` / `cache_write_tokens` in usage | Not read | We can't see whether caching works. |

The SDK already has every field: `ChatRequest.sessionId`, `.cacheControl`,
`.promptCacheKey`, `.promptCacheOptions`, and
`ChatUsage.promptTokensDetails?.cachedTokens` / `.cacheWriteTokens`.
No SDK change is needed.

## Steps to use all of it

1. **`session_id`:** a UUID per Tag session, sent with every request.
2. **Top-level `cache_control: {type: ephemeral}`.** Unverified: whether
   OpenRouter ignores it for providers that don't support it. Check with
   one request against DeepSeek with the field set.
3. **TTL:** 5 minutes by default. Interactive users often pause longer, so
   the cache expires and is written again. `"ttl": "1h"` costs 2× on writes
   instead of 1.25×; probably worth it for long sessions. Sticky routing
   also expires after 10 idle minutes, another reason for `session_id`.
4. **Show cache hits** in the [status line](tools.md#the-status-line), e.g.
   `ctx 12.3k (89% cached)`, so the other steps can be verified instead of
   assumed.
5. **Keep the prefix stable** (a rule for future work):
   - render the [system prompt](system-prompt.md) once per session
   - no live data (date, git status) in it
   - tools always in the same order
   - send reasoning fields back unchanged
   - never set `provider.order` (it turns off sticky routing)

A guess, not measured: DeepSeek sessions already hit the cache from the
second or third request on. Step 4 would show it; until then the only check
is OpenRouter's Activity page.

## Gotchas

- Minimum cacheable prompt sizes: 1,024 tokens for OpenAI, 512–4,096 for
  Claude depending on the model. A short first turn won't be cached.
- From GPT-5.6, OpenAI charges 1.25× for cache writes even with automatic
  caching. In an agent loop the reads dominate, so this rarely matters.
