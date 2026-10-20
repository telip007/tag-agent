---
title: Models and providers
summary: How ModelKit connects Tag to OpenRouter, ChatGPT plans (Codex) and OpenCode Go: neutral messages, one adapter per wire format, the catalogue, sign-in, credentials and settings, and the gotchas from the providers' docs.
updated: 2026-10-20
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

Cache request policy and per-format cache usage accounting are documented in
[prompt caching](prompt-caching.md). All adapters retain optional cache reads
and writes; the agent shows the latest completed reply's reported counts in its status panel.

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

**Several Tag processes at once.** Every write holds a
[`FileLock`](../../Sources/ModelKit/FileLock.swift) (`flock(2)`) on a
`.<file>.lock` beside the file, so concurrent read-modify-writes don't lose
each other's changes. A ChatGPT refresh holds `.chatgpt-refresh.lock` across
the token request, then re-reads the account. Refresh tokens rotate, and the
server revokes the sign-in when one is spent twice
(`refresh_token_reused`), so a second process waiting on the lock uses the
first one's fresh tokens instead of refreshing again.

A lock file is created with `.withoutOverwriting`: two processes that
both found it missing and created it with `FileManager.createFile` replaced
each other's file and locked two different inodes, so the lock did nothing
(the two-session refresh test caught it under parallel tests).

**Keeping the agent out.** Tag runs shell commands and reads files that the
model chooses, so a `0600` file alone doesn't keep a prompt-injected model away
from it. [`ProtectedPaths`](../../Sources/TagKit/ProtectedPaths.swift) makes
the file tools refuse the config directory, also through `..` and symbolic
links, and makes `code_search` refuse it as a search path. `bash` refuses
commands that name the directory in any spelling (absolute, `~/`,
`$HOME/`, relative to home). It is a guard, not a sandbox: a shell command
can still reach the file in ways a check of its text doesn't see. The
macOS Keychain was considered and left out for now
([0012](../decisions/0012-model-providers.md)).

## Errors

[`ProviderError`](../../Sources/ModelKit/ProviderError.swift) says what went
wrong and gives the user's next step (`recoverySuggestion`). The agent shows
both. A usage limit links to the provider's usage page:
`chatgpt.com/settings/usage` for ChatGPT, the OpenCode console for Go. The
documented ChatGPT plan codes, such as
`subscription_sharing_usage_limit_exceeded` and `…_user_not_eligible`, are
mapped in [`ResponsesStream`](../../Sources/ModelKit/Wire/ResponsesStream.swift).

## Gotchas

### Sign-in with ChatGPT review (2026-10-19)

Compared with the [cookbook](https://developers.openai.com/cookbook/articles/sign-in-with-chatgpt)
and its linked integration guides, the registration parameters, loopback
callback, saved issued client ID, refresh serialization, public endpoints,
and completion handling follow the documented approach. This is a source
review; a successful ChatGPT plan request is still unverified.

Validation: `TAG_LIVE_TESTS=0 make check` passed, including the 80% coverage
gate (91.3% measured). `make wiki-lint` passed after this review was added.
The existing tests use fixtures; they do not establish live ChatGPT access.

Known differences that need follow-up:

- **ID-token signature:** `IDTokenClaims.validated` checks claims but skips
  the signature. Regardless of its OIDC TLS rationale, the
  [sign-in guide](https://developers.openai.com/siwc/token-sharing-open-source/sign-in#4-validate-the-id-token-and-chatgpt-plan-permission)
  explicitly requires signature verification using OpenAI's JWKS.
- **Account registrations:** `Credentials` stores one account and one client
  ID. Sign-out retains that ID, and the next sign-in reuses it; there is no
  separate new-profile path. The
  [accounts guide](https://developers.openai.com/siwc/token-sharing-open-source/profiles-and-sessions)
  requires separate registrations and credentials for account/workspace
  switching. Signing out alone does not make an existing client switch its
  bound workspace.
- **Tool encoding:** `ResponsesChatModel.body` sends flat function tools in
  top-level `tools`. The current
  [preview limitations](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations)
  require function/custom tools in namespaces or `additional_tools` input
  items. OpenRouter adapter success does not validate this ChatGPT route.
- **Consent declined:** `ChatGPTSignIn.account` throws before saving an
  identity-only sign-in. The
  [recovery guide](https://developers.openai.com/siwc/token-sharing-open-source/errors-and-recovery)
  instead retains the sign-in with plan usage disabled.

**Business denial evidence boundary:** The cookbook names eligible Plus and
Pro users. No public documentation found in this review maps
`3p_delegated_access_policy_denied` to a specific Business admin control.
Eligibility/workspace policy is a plausible explanation, not a verified
account-specific diagnosis. These implementation differences do not explain
a denial shown by OpenAI before the callback. OpenAI support must confirm
Business eligibility or a tenant-specific policy; no bypass was attempted.

### Other provider gotchas

- **Configured interleaving needs an empty field too.** Native prompt-evaluation
  diagnostics on 2026-10-20 reconstructed a tool follow-up: omitting
  `reasoning_content` returned HTTP 400, while an empty value was accepted.
  `ChatCompletionsChatModel` now emits own-format replay or an empty string
  whenever `reasoningField` is configured; `nil` still omits it and foreign
  reasoning is never copied. The regression covers tool and text turns.
  [DeepSeek documents this requirement for tool-enabled conversations](https://api-docs.deepseek.com/guides/thinking_mode/).
  This diagnostic does not establish why two earlier native benchmark jobs
  timed out, nor does it measure cache savings or prompt superiority.

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
- **One streaming path for every format.** Each adapter has a `WireDecoder`
  (Chat Completions, Anthropic, Gemini, and `ResponsesDecoder`), and
  [`WireStream`](../../Sources/ModelKit/Wire/WireStream.swift) runs encoding,
  the request and decoding in a detached task. A decoder may map HTTP errors
  its own way: Responses maps the ChatGPT plan codes (`ResponsesError`).
  The Responses adapter first had its own copy of this (written in
  parallel), merged into `WireStream` on 2026-10-19.
- **Gateways end Anthropic and Gemini streams with `data: [DONE]`** too.
  OpenRouter's Anthropic-compatible route sends it after `message_stop`, so
  every decoder ignores it.
- **Live adapter tests:** `TAG_LIVE_TESTS=1 swift test --filter
  LiveAdapterTests` (with `OPENROUTER_API_KEY`) sends a real tool call and
  its result through the Chat Completions, Responses and Anthropic Messages
  adapters via OpenRouter, which serves all three formats. They're skipped
  otherwise. They passed on 2026-10-19. Gemini's native format needs a
  Google or OpenCode Go key.
- **OpenCode Go rejects a request without `x-opencode-session`** (HTTP 400
  `MissingSessionID`) before it even checks the key. With the header and no
  key it answers 401 "Go requires a credential", which Tag reports as sign in
  again. Its model list needs no key. (Probed live on 2026-10-19.)
- **OpenAI's authorize page is behind a browser check.** Fetching it from a
  script gets a 403 challenge, so the sign-in can only be tried in a real
  browser, which is how Tag opens it.
- **ChatGPT Business workspaces refuse the sign-in** with
  `3p_delegated_access_policy_denied` in the browser (seen 2026-10-19, also
  reported by users of other open-source agents). The cookbook names
  eligible Plus and Pro plans; no documented Business override was found.
  This does not establish the precise policy behind an individual denial.
  A personal Plus or Pro workspace is the documented test path, but an
  already-issued client remains bound to its original workspace. The
  Codex CLI's own sign-in still works for Business because it is OpenAI's app;
  using it from Tag would mean posing as the Codex CLI on an undocumented
  backend, which was left as an open decision: see
  [Codex CLI route](../designs/codex-cli-route.md).
- **OpenCode Go works live**: the maintainer connected a key and chatted
  through it (2026-10-19).
- **Not tried live yet**: a successful ChatGPT sign-in (only a Business
  workspace was tried), tested so far against fixtures and a local loopback
  listener. Unknowns: the field names for context and reasoning levels
  in `/v1/models`; whether Go's Anthropic route accepts adaptive thinking;
  Gemini's `thinkingLevel` values.
