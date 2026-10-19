---
title: Model picker design
summary: The brainstormed design for choosing models: the agreed behaviour (defaults, onboarding, /model and quick switch) and the three picker mockups, of which the search-first overlay was chosen.
updated: 2026-10-19
---

# Model picker design

Brainstormed with the maintainer on 2026-10-19 before
[0011](../decisions/0011-model-providers.md). The mockups were shown in the
browser and are kept here as text. How it was built is on
[models and providers](../concepts/model-providers.md).

## What was agreed

- **There is always a default.** Once the user has configured a model, Tag
  starts with the model and reasoning effort they used last.
- **First run:** when no API key and no sign-in exist, onboarding guides the
  user. They connect providers (a ChatGPT browser sign-in, OpenCode Go and
  OpenRouter API keys), pick a first model, and land in the chat.
- **Providers in scope:** OpenRouter, ChatGPT plans (Codex) and OpenCode Go.
- **`/model`** opens the interactive picker, and it is also in the command
  palette.
- **`/model <provider>/<model>`** switches straight away. Without an exact
  match it opens the picker with the text in the search box.
- **Switching models mid-session keeps the conversation.**

## The mockups

Three shapes were shown. **A was chosen.**

### A: Search-first overlay (chosen)

One search box filters the models of every provider. Recent models come
first, then all models grouped by provider. A detail line shows the
highlighted model, and effort is changed with ←→.

```text
╭─ model ───────────────────────────────────────────────╮
│ › gpt-5                                               │
│                                                       │
│ recent                                                │
│  ● GPT-5.5 Codex         codex pro    included        │
│   Kimi K3                 opencode go  included       │
│ codex pro                                             │
│   GPT-5.5                 400k ctx     included       │
│   GPT-5.5 mini            400k ctx     included       │
│ openrouter                                            │
│   GPT-5.5                 400k ctx     $1.25 / $10    │
│                                                       │
│ reasoning ◂ medium ▸   ↵ use · ←→ effort · ^a add provider │
╰───────────────────────────────────────────────────────╯
```

### B: Provider → model columns

Providers on the left with their sign-in state, their models on the right,
and details below. Built for browsing rather than searching. It also
assumed a usage meter, which ChatGPT plans don't offer (see
[0011](../decisions/0011-model-providers.md)).

```text
╭─ model ───────────────────────────────────────────────╮
│ providers          │ models                           │
│  codex pro      ✓  │  ● GPT-5.5 Codex                 │
│   opencode go    ✓  │   GPT-5.5                        │
│   openrouter     ✓  │   GPT-5.5 mini                   │
│   anthropic      +  │                                  │
│─────────────────────┴──────────────────────────────────│
│ GPT-5.5 Codex · 400k ctx · included in plan             │
│ 5h limit 38% used · resets 14:20                       │
│ ↑↓ move · ←→ column · ↵ use · / search                 │
╰─────────────────────────────────────────────────────────╯
```

### C: Inline above the input

Typing `/model` pops a compact list over the input, like completion. It is
fast and minimal, with no full overlay.

```text
  ┌──────────────────────────────────────────────┐
  │  GPT-5.5 Codex     codex pro    ●           │
  │   Kimi K3           opencode go             │
  │   DeepSeek V4.1     openrouter   $0.27      │
  └──────────────────────────────────────────────┘
╭──────────────────────────────────────────────────╮
│ › /model gp                                      │
╰──────────────────────────────────────────────────╯
```

The model names and numbers in the mockups were placeholders.
