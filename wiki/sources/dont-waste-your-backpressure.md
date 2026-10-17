---
title: Don't waste your back pressure
summary: Moss's essay on automated feedback as the lever for agent autonomy.
updated: 2026-10-17
---

# Don't waste your back pressure

Raw capture: [raw/2026-10-17-dont-waste-your-backpressure.md](../raw/2026-10-17-dont-waste-your-backpressure.md).

## Summary

- **Back pressure** is the automated feedback an agent gets on quality and
  correctness: builds, type checkers, linters, tests, rendered UIs, proofs.
- Without it, the human *is* the feedback loop and spends attention on
  trivia (a missing import) instead of hard problems. With it, agents can
  loop until the tools are satisfied and take on longer tasks.
- Expressive type systems and good error messages are back pressure: they
  make invalid states unrepresentable, and the messages flow straight back
  into the model.
- Agents need *access* to the feedback (shell, build tools, browser or LSP
  MCPs), not just file editing.
- For spec-driven work, generate artifacts (e.g. docs from an OpenAPI schema)
  so the agent can compare intent with result.

## How we applied it

- [0002 Maximum backpressure](../decisions/0002-maximum-backpressure.md) and
  [Backpressure setup](../concepts/backpressure-setup.md).
- The SDK is generated from the OpenAPI spec, so API drift shows up as a
  compile error instead of a runtime surprise.
