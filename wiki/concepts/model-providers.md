---
title: Models and providers
summary: How ModelKit connects Tag to OpenRouter, ChatGPT plans (Codex) and OpenCode Go: neutral messages, one adapter per wire format, the catalogue, sign-in, credentials and settings, and the gotchas from the providers' docs.
updated: 2026-10-19
---

# Models and providers

Why it is shaped this way: [0012](../decisions/0012-model-providers.md). The
user-facing design: [model picker](../designs/model-picker.md).

## Layers

```text
Agent ──[Message]──▶ ActiveModel.chatModel ─▶ adapter (wire format) ─▶ HTTPTransport
  ▲                        ▲
  └─ model() each call ────┴── ModelSelection ◀── ProviderRegistry ◀── providers
```

- [`Conversation.swift`](../../Sources/ModelKit/Conversation.swift) holds the
  neutral types. `Message` (system, user, assistant, tool) has an
  `AssistantMessage` with text, reasoning, tool calls and `replay`, which
  carries provider data tagged with its `WireFormat`. The file also defines
  `ChatModel`, whose `reply(to:tools:options:onDelta:)` streams
  `ReplyDelta`s, and `ReplyOptions`, which hold the reasoning effort and a
  per-conversation `sessionID`.
- [`Catalogue.swift`](../../Sources/ModelKit/Catalogue.swift) defines
  `ProviderID` (with aliases for `/model`), `ModelRef` (`provider/model`,
  split at the first `/`), `ModelEntry` (name, context, `Pricing`, efforts,
  format), `ConnectMethod` and the `Provider` protocol.
  [`ProviderRegistry`](../../Sources/ModelKit/ProviderRegistry.swift) fetches
  every connected provider's catalogue in parallel and reports failures per
  provider.
- [`Agent`](../../Sources/TagKit/Agent.swift) reads the
  [`ActiveModel`](../../Sources/TagKit/ActiveModel.swift) before every model
  call. When its `ModelRef` changed, `ConversationState.follow` re-renders
  only the system prompt. A failed call becomes
  `AgentEvent.failure(message:recovery:)`.

## Wire formats

| Format | Adapter | Used by |
| --- | --- | --- |
| OpenRouter SDK | [`OpenRouterChatModel`](../../Sources/ModelKit/Providers/OpenRouterChatModel.swift) | OpenRouter |
| Chat Completions | [`ChatCompletionsChatModel`](../../Sources/ModelKit/Wire/ChatCompletionsChatModel.swift) | most OpenCode Go models |
| Responses | [`ResponsesChatModel`](../../Sources/ModelKit/Wire/ResponsesChatModel.swift) | Codex, Go's GPT/Grok/Muse models |
| Anthropic Messages | [`AnthropicChatModel`](../../Sources/ModelKit/Wire/AnthropicChatModel.swift) | Go's Claude, Qwen, MiniMax models |
| Gemini | [`GeminiChatModel`](../../Sources/ModelKit/Wire/GeminiChatModel.swift) | Go's Gemini model |

Each adapter is built from a
[`WireEndpoint`](../../Sources/ModelKit/Wire/WireEndpoint.swift): the URL,
the model id, the provider (for errors), a headers closure read per request
(so tokens can refresh) and an `HTTPTransport`. Encoding, the request and
decoding run in a detached task, because the agent runs on the main actor
with the UI. Encoding a long conversation there would hold up typing (see
[terminal UI](terminal-ui.md#keeping-frames-cheap)).
[`HTTP.swift`](../../Sources/ModelKit/HTTP.swift) splits the body into
lines itself, because `AsyncBytes.lines` drops the empty lines that end
server-sent events.

## Providers

- **OpenRouter**
  ([`OpenRouterProvider`](../../Sources/ModelKit/Providers/OpenRouterProvider.swift)):
  the key comes from `OPENROUTER_API_KEY` or the store. The catalogue lists
  only models whose `supported_parameters` include `tools`, because the
  agent needs them. Prices are converted from per-token strings to
  per-million figures.
- **ChatGPT plan / Codex**
  ([`CodexProvider`](../../Sources/ModelKit/Providers/CodexProvider.swift),
  [`Auth/`](../../Sources/ModelKit/Auth/ChatGPTSignIn.swift)): uses the
  official *Sign in with ChatGPT* for open-source apps.
  - **First sign-in.** It registers with `client_id=dynamic_agent_client`
    and `agent_name_hint`, using PKCE S256 with fresh `state` and `nonce`,
    and an opaque `ext_agent_host_id` (`urn:uuid:`) that is made once and
    kept. The loopback redirect goes to `http://127.0.0.1:1455/auth/callback`;
    later sign-ins may use another port. The callback brings the issued
    `client_id`, which is saved and reused.
  - **Tokens.** The ID token's `iss`, `aud`, `exp` and `nonce` are checked,
    and the `chatgpt.tokens.use.direct` scope must have been granted. The
    signature isn't checked, because the token comes straight from the
    token endpoint over TLS (OIDC Core 3.1.3.7). Access tokens last an hour
    and refresh 5 minutes before expiry. Refresh tokens rotate, and an actor
    serialises refreshes. A terminal refresh error clears the tokens but
    keeps the client id and host id. Sign-out revokes the refresh token at
    the discovery document's `revocation_endpoint`.
  - **Models and requests.** `GET /v1/models` lists the models
    (`visibility == "list"`, `slug`, `display_name`). Requests go to
    `POST /v1/responses` with `store: false` and `stream: true`, the full
    history every time, system text in `instructions`, and
    `include: ["reasoning.encrypted_content"]` for reasoning models, so
    reasoning survives the next turn.
- **OpenCode Go**
  ([`OpenCodeGoProvider`](../../Sources/ModelKit/Providers/OpenCodeGoProvider.swift)):
  the key comes from `OPENCODE_API_KEY` or the store. The live `/v1/models`
  id list is joined with [models.dev](https://models.dev/api.json) metadata
  ([`ModelsDevCatalogue`](../../Sources/ModelKit/Providers/ModelsDevCatalogue.swift),
  cached for 24 hours in `cache/models-dev.json`, falling back to a stale
  copy). models.dev's `provider.npm` gives each model's format. Every
  request carries Tag's `User-Agent` and `x-opencode-session`, added by an
  internal session wrapper.

## Credentials and settings

[`Storage.swift`](../../Sources/ModelKit/Storage.swift) keeps two files in the
config directory (`$TAG_CONFIG_DIR`, else `$XDG_CONFIG_HOME/tag`, else
`~/.config/tag`). Both are written atomically, the directory with mode `0700`
and the files with `0600`:

- `credentials.json` holds API keys, the ChatGPT account, its host id and its
  client id. API keys in the environment win over stored ones.
- `settings.json` holds `lastModel`, the reasoning effort per model, recent
  models (newest first, at most 6) and whether the one-time ChatGPT plan
  notice was shown.

## Errors

[`ProviderError`](../../Sources/ModelKit/ProviderError.swift) says what went
wrong and gives the user's next step (`recoverySuggestion`). The agent shows
both. A usage limit links to the provider's usage page:
`chatgpt.com/settings/usage` for ChatGPT, the OpenCode console for Go. The
documented ChatGPT plan codes, such as
`subscription_sharing_usage_limit_exceeded` and `…_user_not_eligible`, are
mapped in [`ResponsesStream`](../../Sources/ModelKit/Wire/ResponsesStream.swift).

## Gotchas

- **The ChatGPT plan route rejects many Responses fields**: `temperature`,
  `top_p`, `max_output_tokens`, `metadata`, `user`, `truncation`, and
  `previous_response_id` over HTTP. It also rejects system-role input items.
  Tools are sent with `strict: false`, because the Responses API turns
  strict schemas on by default and Tag's schemas don't meet them.
- **There is no usage meter for ChatGPT plans.** The docs offer only the
  limit error and a link, so the picker can't show "x% used".
- **Replay is per format.** Anthropic thinking blocks and Gemini thought
  signatures must go back verbatim, and Responses reasoning items only with
  their `encrypted_content`. Items of other formats are dropped, so
  switching providers loses the old reasoning but keeps the conversation.
- **Gemini rejects some JSON Schema keys** (`additionalProperties`,
  `$schema`), so the adapter strips them from tool schemas.
- **There are two streaming helpers.** `WireStream` (Chat Completions,
  Anthropic, Gemini) and `ResponsesStream` were written in parallel. Merging
  them into one is a follow-up.
- **OpenCode Go rejects a request without `x-opencode-session`** (HTTP 400
  `MissingSessionID`) before it even checks the key. With the header and no
  key it answers 401 "Go requires a credential", which Tag reports as sign in
  again. Its model list needs no key. (Probed live on 2026-10-19.)
- **OpenAI's authorize page is behind a browser check.** Fetching it from a
  script gets a 403 challenge, so the sign-in can only be tried in a real
  browser, which is how Tag opens it.
- **Not tried live yet**: a real ChatGPT sign-in, and OpenCode Go requests.
  They are tested against recorded-shape fixtures and a local loopback
  listener only. Unknowns: the field names for context and reasoning levels
  in `/v1/models`; whether Go's Anthropic route accepts adaptive thinking;
  Gemini's `thinkingLevel` values.
