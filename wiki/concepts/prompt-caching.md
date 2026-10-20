---
title: Prompt caching
summary: Provider-aware cache requests, stable conversation prefixes and reported cache reads and writes across all ModelKit adapters.
updated: 2026-10-20
---

# Prompt caching

Tag enables provider-side prompt caching while sending the full conversation
on every request. It does not cache generated answers locally. Policy:
[0013](../decisions/0013-prompt-caching.md); design and validation plan:
[prompt caching implementation](../designs/prompt-caching.md).

## Requests by provider

| Provider / format | Cache behavior |
| --- | --- |
| OpenRouter | A stable `session_id` enables sticky routing from the first successful request. Top-level `cache_control: {type: ephemeral}` enables automatic Anthropic caching. Anthropic and Qwen model families, `deepseek/deepseek-v3.2` (Alibaba), and `openrouter/` routers with an unresolved target also get explicit markers on the last system message and the last two user/result turns. A batch of tool results counts as one turn. Other models retain native automatic caching. |
| ChatGPT plan / Codex, Responses | A stable `prompt_cache_key` (at most 64 characters) and the complete history use OpenAI's automatic caching. No model-specific retention overrides. |
| OpenCode Go, all formats | The same conversation UUID goes in `x-opencode-session` on every request, including tool iterations. |
| Go, Anthropic Messages | Explicit ephemeral markers on the system block, final tool definition and last two user turns; at most four breakpoints. Tool-result batches are merged before marking. Signed thinking blocks are replayed untouched. |
| Go, Responses | The same automatic caching and `prompt_cache_key` as the Responses adapter above. |
| Go, Chat Completions | Native automatic prefix caching. No OpenAI-only request fields are sent to unrelated compatible models. |
| Go, Gemini | Native implicit caching. No cache objects, extra storage charges or unsupported cache-management routes are introduced. |

Implementation: [OpenRouterCaching](../../Sources/ModelKit/Providers/OpenRouterCaching.swift),
[OpenRouterChatModel](../../Sources/ModelKit/Providers/OpenRouterChatModel.swift),
[AnthropicChatModel](../../Sources/ModelKit/Wire/AnthropicChatModel.swift),
[ResponsesChatModel](../../Sources/ModelKit/Wire/ResponsesChatModel.swift),
[OpenCodeGoModels](../../Sources/ModelKit/Providers/OpenCodeGoModels.swift).

## Keeping the prefix reusable

- `ConversationState` renders the system prompt once per selected model;
  date notes are appended to user messages. History and tool order stay stable.
- Model switches retain history and the session ID, but change the model and
  system prompt, so they can cause a cold cache. `/clear` makes a new UUID.
- JSON object keys, including tool schemas, are sorted in every request.
  The wire adapters use `JSONValue.encoded()`; the SDK's OpenAPI runtime
  defaults to sorted keys. Array order and reasoning replay stay unchanged.
- Anthropic's old request boundary remains explicitly marked alongside the
  new one. Its cache lookup only looks back 20 blocks from a breakpoint;
  a large new turn must not hide the earlier entry.
- Tag never sets `provider.order`, which would override OpenRouter stickiness.

## Observing cache use

[`Usage`](../../Sources/ModelKit/Conversation.swift) carries optional
`cachedInputTokens` and `cacheWriteInputTokens` per reply:

| Format | Read field | Write field |
| --- | --- | --- |
| OpenRouter / Chat Completions | `prompt_tokens_details.cached_tokens` | `prompt_tokens_details.cache_write_tokens` |
| Responses | `input_tokens_details.cached_tokens` | `input_tokens_details.cache_write_tokens` |
| Anthropic Messages | `cache_read_input_tokens` | `cache_creation_input_tokens` |
| Gemini | `usageMetadata.cachedContentTokenCount` | Not reported |

`nil` means unreported; zero means a reported zero. Anthropic reports ordinary
input, cache reads and cache writes separately; Tag merges partial stream
updates per field, then sums them once. Other formats already include cache
reads in their input total. Output includes reasoning where the API exposes it.

The sidebar and `StatusLine.text` show the latest completed reply's reported metrics,
for example `cache read 9k · write 1k`. Missing metrics are omitted; an unknown
reply, model switch or `/clear` clears stale counts. Counts are not accumulated
across turns. A failed or in-flight request retains the previous completed
reply's counts unless the model changed or the conversation was cleared.
The existing session cost still sums only provider-reported
cost; Tag does not estimate savings or subscription charges.

## Gotchas and evidence boundaries

- Caching is subject to model minimum prompt sizes, expiry and provider
  routing. An opt-in is not proof of a hit, and an absent metric is not zero.
- Default Anthropic retention is five minutes. One-hour writes cost more;
  this implementation does not force longer TTLs or OpenAI's model-specific
  retention settings. Gemini explicit cache objects also have storage costs.
- Unresolved OpenRouter routers get content markers so Alibaba routes can
  opt in too. When a router chooses Gemini, those markers can invoke explicit
  caching with storage charges. Fixed Gemini model slugs use implicit caching.
  [Auto Router](https://openrouter.ai/docs/guides/routing/routers/auto-router)
  can choose a different allowed model between turns; Tag does not pin it.
- OpenRouter's automatic control is provider-specific. Alibaba requires
  content markers; setting only top-level `cache_control` misses that route.
- Removing old markers does not remove the conversation content. Opt-in
  OpenRouter messages always retain their content-parts representation,
  even when their old marker moves off the last two turns.
- Fixture tests exercise all five usage decoders, partial Anthropic updates,
  large tool batches, signed replay, stable schema encoding, UI propagation
  and missing/zero metrics. They prove the implementation contract; live
  cache-hit rates and monetary savings remain unmeasured.

## Sources checked on 2026-10-20

- [OpenRouter prompt caching](https://openrouter.ai/docs/features/prompt-caching):
  sticky routing, automatic vs explicit providers, default TTLs and usage.
- [OpenAI prompt caching](https://developers.openai.com/api/docs/guides/prompt-caching):
  stable prefixes, automatic caching, cache keys and Responses usage fields.
- [Anthropic prompt caching](https://platform.claude.com/docs/en/build-with-claude/prompt-caching):
  four breakpoints, 20-block lookup and separate cache token accounting.
- [Gemini generateContent caching](https://ai.google.dev/gemini-api/docs/generate-content/caching):
  implicit caching and the separate explicit-cache lifecycle.

The earlier [OpenRouter source capture](../sources/openrouter-prompt-caching.md)
remains available as historical research.
