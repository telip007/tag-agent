---
title: OpenRouter prompt caching
summary: OpenRouter's caching guide: automatic vs cache_control providers, sticky routing, session_id, TTLs and usage fields.
updated: 2026-10-18
---

# OpenRouter prompt caching

Raw capture: [raw/2026-10-18-openrouter-prompt-caching.md](../raw/2026-10-18-openrouter-prompt-caching.md).

## Summary

- **Automatic** for most providers (OpenAI, DeepSeek, Gemini 2.5, Grok,
  Moonshot). **Opt-in** for Anthropic and Alibaba via `cache_control`.
- **Top-level `cache_control`** (Anthropic, Vertex, Azure, Bedrock): one
  field, and the breakpoint follows the end of the conversation. Default
  TTL 5 minutes; `"ttl": "1h"` costs 2× on writes instead of 1.25×.
- **Sticky provider routing** keeps a conversation on the provider that
  holds its cache. Without `session_id` it starts only after the first
  cache hit and keys on a hash of the first system and first non-system
  message. With `session_id` it starts on the first request. It expires
  after 10 minutes idle and is off when `provider.order` is set.
- **Usage** reports `prompt_tokens_details.cached_tokens` and
  `cache_write_tokens`.

## How we use it

See [prompt caching](../concepts/prompt-caching.md) for what Tag does today
and the steps to use all of this.
