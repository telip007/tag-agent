---
title: Model providers and user-chosen models
summary: Tag talks to OpenRouter, ChatGPT plans (Codex) and OpenCode Go through a provider-neutral ModelKit module with one adapter per wire format, and the user picks the model; nothing is hard-coded.
updated: 2026-10-19
---

# 0012 Model providers and user-chosen models

## Context

Tag talked to one hard-coded OpenRouter model through the OpenRouter SDK, and
the agent loop used the SDK's generated message types. The maintainer wanted
to use their own subscriptions as well: a ChatGPT plan (Codex) and OpenCode
Go. They also wanted to choose the model themselves, with the choice
remembered between sessions.

What the providers' official documentation says (read 2026-10-19):

- **ChatGPT plan usage** ("Sign in with ChatGPT" for open-source and locally
  hosted apps): the app registers itself on its first sign-in, with no shared
  client id and no secret. The first authorize request uses
  `client_id=dynamic_agent_client`, and the callback returns the issued id.
  Sign-in is a PKCE browser flow with a loopback redirect on `127.0.0.1`.
  Requests go to the public Responses API (`api.openai.com/v1/responses`)
  with `store: false` and `stream: true`. `GET /v1/models` lists the
  account's models. There is no usage meter: a usage-limit error links to
  ChatGPT's usage settings. See [models and providers](../concepts/model-providers.md).
- **OpenCode Go**: one API key. Each model is served in one of four formats
  (Chat Completions, Responses, Anthropic Messages, Gemini). Clients must
  send their own `User-Agent` and a stable `x-opencode-session` header for
  each conversation.

## Decision

1. **A new `ModelKit` module** owns everything provider-related: neutral
   conversation types (`Message`, `AssistantMessage`, `ToolCall`, `ToolSpec`,
   `Usage`), the `ChatModel` and `Provider` protocols, the catalogue
   (`ModelEntry`, `ModelRef`), credentials and settings, an HTTP transport
   with server-sent events, and the providers. It has no UI. `TagKit`
   depends on it, and it could become a published package later. It isn't
   one yet: Swift already has multi-provider and ChatGPT sign-in packages,
   so we build our own first and decide once it has settled.
2. **One adapter per wire format**, not per provider: Chat Completions,
   Responses, Anthropic Messages and Gemini, plus OpenRouter through its SDK.
   A provider picks the adapter from the model's `WireFormat`. Provider data
   a model needs on its next turn (encrypted reasoning, thinking signatures)
   rides on `AssistantMessage.replay`, tagged with its format. An adapter
   sends back only its own items, so a conversation survives a switch to
   another provider.
3. **Only documented routes.** Codex goes through the official Sign in with
   ChatGPT flow and `api.openai.com/v1`, never through the Codex CLI's
   private backend.
4. **No hard-coded model.** `Settings.lastModel` and its reasoning effort
   start the next session. Without them, onboarding asks the user to connect
   a provider and pick a model. `/model` opens a search-first picker, and
   `/model <provider>/<model>` switches straight away.
5. **The agent reads the active model before every call.** Switching keeps
   the conversation and re-renders only the system prompt, so the new model
   knows its own name.
6. **A failed model call doesn't end the session.** It becomes
   `AgentEvent.failure` with a recovery hint, for example *Manage usage* for
   a usage limit, and the agent waits for the next message.
7. **Credentials live in `credentials.json` with mode `0600`** in the config
   directory (`$TAG_CONFIG_DIR`, `$XDG_CONFIG_HOME/tag` or `~/.config/tag`).
   Files are written atomically. API keys in the environment override stored
   ones. We chose files over the Keychain for testability and for the
   provider documentation's guidance, which says to keep tokens in
   owner-only files.

## Consequences

- The agent loop and its tests no longer depend on the OpenRouter SDK's
  generated types. Only the OpenRouter adapter does.
- Prompt caching across a model switch is lost by design: the system prompt
  changes.
- Codex models report no cost. The status line shows `$0.00` for them, and
  the session panel says "Using ChatGPT plan".
- OpenCode Go metadata (names, context, prices, efforts, formats) comes from
  models.dev, cached for a day, because Go's own model list carries only ids.
