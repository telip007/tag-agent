---
title: Codex CLI route for ChatGPT plans
summary: The undocumented route the Codex CLI uses to reach ChatGPT plans (also Business workspaces, which refuse Tag's official sign-in): how it works, its risks, and the options; not built, decision open.
updated: 2026-10-19
---

# Codex CLI route for ChatGPT plans

**Status: not built. The decision is open.** Tag reaches ChatGPT plans only
through the official *Sign in with ChatGPT* for open-source apps
([0012](../decisions/0012-model-providers.md), point 3). This page collects
what is known about the other route, so it can be decided with everything
in one place.

## Why it came up

On 2026-10-19 the official sign-in failed for the maintainer's ChatGPT
Business workspace. The browser showed `3p_delegated_access_policy_denied`
(see [models and providers](../concepts/model-providers.md#gotchas)).
Users of other open-source agents report the same thing. Plan usage in
third-party apps is offered to personal Plus and Pro plans, and no admin
setting for Business was found. The same account signs in fine with the
Codex CLI, which is OpenAI's own app.

## How the route works

All of these values are public in OpenAI's open-source Codex CLI
([openai/codex](https://github.com/openai/codex): `codex-rs/login/src/server.rs`,
`codex-rs/login/src/auth/manager.rs`, `codex-rs/model-provider/src/auth.rs`).

| | Official route (Tag today) | Codex CLI route |
| --- | --- | --- |
| Client | Registered dynamically per user (`dynamic_agent_client` → `oaiapp_…`) | The Codex CLI's fixed client id `app_EMoamEEZ73f0CkXaXp7hrann` |
| Authorize | `auth.openai.com/api/accounts/authorize` | `auth.openai.com/oauth/authorize`, plus `id_token_add_organizations=true`, `codex_cli_simplified_flow=true`, `originator` |
| Redirect | `http://127.0.0.1:<port>/auth/callback` | `http://localhost:1455/auth/callback` (device-code login also exists) |
| Scopes | `… resource.invoke chatgpt.tokens.use.direct` | `openid profile email offline_access` (+ connector scopes) |
| Inference | `api.openai.com/v1/responses` (public API) | `chatgpt.com/backend-api/codex/responses` (private backend) |
| Models | `GET api.openai.com/v1/models` | `GET chatgpt.com/backend-api/codex/models` |
| Extra headers | none | `ChatGPT-Account-ID` (from the ID token's `https://api.openai.com/auth` claim), `originator` |
| Plans | personal Plus and Pro | also Business workspaces |

The request body is the Responses format, so Tag's
[`ResponsesChatModel`](../../Sources/ModelKit/Wire/ResponsesChatModel.swift)
would mostly carry over. What's new: the sign-in, the headers and the
models endpoint.

## Risks

- **Tag would be posing as OpenAI's app.** It would send the Codex CLI's
  client id and `originator`. OpenAI publishes a separate flow for
  third-party apps, so using this one is plausibly against its terms. The
  account involved belongs to the user's employer.
- **An undocumented API.** `backend-api/codex` can change or start rejecting
  other clients at any time, with no notice and no error codes to rely on.
- **Reported logouts.** A user of another agent reports being signed out
  about every 24 hours on this route. *Guess:* the Codex CLI and the agent
  refresh the same rotating tokens, so each one's refresh revokes the
  other's.
- **The workspace admin can't see or limit it** the way the official route's
  per-app usage cap allows.

## Options

1. **Don't build it** (the current state). Business users choose a personal
   Plus or Pro workspace, or use OpenRouter or OpenCode Go. Signing in with a
   different workspace needs a **new registration**: the issued client id is
   bound to the workspace, and Tag reuses it today. Making that possible is
   a fix worth doing anyway.
2. **Build it as a separate, opt-in provider**, for example "ChatGPT (Codex
   CLI, unofficial)" with its own provider id (`codex-cli`). It would never
   be offered by default, would warn once before signing in, and would keep
   its own tokens apart from the official provider and from the Codex CLI.
3. **Read the Codex CLI's own `~/.codex/auth.json`** instead of signing in.
   No new sign-in code, but Tag would refresh the Codex CLI's tokens. That
   is the same rotating-token race the [cross-process lock](../concepts/model-providers.md#credentials-and-settings)
   prevents within Tag, and it would sign the Codex CLI out. Not recommended.

**Recommendation:** first make option 1 work properly, with a new
registration for another workspace. Build option 2 only if a Business plan
has to be used through Tag. Never option 3.
