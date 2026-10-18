# OpenRouter prompt caching — capture

- URL: https://openrouter.ai/docs/guides/best-practices/prompt-caching.md
- Captured: 2026-10-18
- Copyright belongs to OpenRouter. This file holds excerpts and notes only.

## Excerpts

> Most providers automatically enable prompt caching, but note that some
> (see Alibaba and Anthropic below) require you to enable it on a
> per-message basis.

> By default, OpenRouter identifies conversations by hashing the first
> system (or developer) message and the first non-system message in each
> request, so requests that share the same opening messages are routed to
> the same provider.

> When `session_id` is set, sticky routing activates on any successful
> request — even before cache usage is observed — so that subsequent
> requests in the same session benefit from prompt caching from the start.
> Without `session_id`, sticky routing only activates after a cache hit is
> detected.

> Sticky sessions expire after **10 minutes** of inactivity.

> Sticky routing is not used when you specify a manual provider order via
> `provider.order`

> **Automatic caching**: Add a single `cache_control` field at the top level
> of your request. The system automatically applies the cache breakpoint to
> the last cacheable block and advances it forward as conversations grow.
> Best for multi-turn conversations.

> By default, the cache expires after 5 minutes, but you can extend this to
> 1 hour by specifying `"ttl": "1h"` in the `cache_control` object.

## Notes

- Price multipliers in the page: DeepSeek reads 0.1×, writes 1×; Anthropic
  reads 0.1×, writes 1.25× (5 min) or 2× (1 h); OpenAI reads 0.25–0.5×,
  writes free before GPT-5.6 and 1.25× from GPT-5.6; Gemini, Grok, Moonshot
  reads 0.25×.
- Minimum cacheable prompt: 1,024 tokens for OpenAI; 512–4,096 for Claude
  depending on the model; 1,024 (Flash) / 4,096 (Pro) for Gemini 2.5.
- Top-level `cache_control` is supported on the Anthropic, Vertex AI, Azure
  and Bedrock providers. Explicit per-block breakpoints: at most four.
- `session_id` (body) or `x-session-id` (header), at most 256 characters;
  falls back to `prompt_cache_key`. It also groups requests on the Logs →
  Sessions page.
- Usage reports `prompt_tokens_details.cached_tokens` and
  `cache_write_tokens`; the generation API reports `cache_discount`.
