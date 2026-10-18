---
title: Tetrate system prompts guide
summary: Tetrate's guide to system prompt components, design patterns, testing and dynamic prompts.
updated: 2026-10-18
---

# Tetrate system prompts guide

Raw capture: [raw/2026-10-18-tetrate-system-prompts.md](../raw/2026-10-18-tetrate-system-prompts.md).

## Summary

- **Components:** role, communication style, output format, knowledge
  boundaries (date, no internet), and behaviour when unsure (ask, or say
  you don't know).
- **Be specific** about the role rather than "helpful assistant".
- **Cost:** the system prompt is sent with every request.
- **Treat the prompt as code:** measurable criteria, a test set of typical,
  boundary, adversarial and ambiguous cases, a fixed model and parameters
  when comparing, one change at a time, the reason for each change
  recorded.
- **Dynamic prompts:** build from parts; inject task-specific instructions
  only when the task comes up.

## How we use it

- The testing advice is rule 11 in
  [system prompt](../concepts/system-prompt.md), and depends on the
  headless mode and saved conversations listed in
  [mini-swe-agent](mini-swe-agent.md).
- We discount the persona advice for a coding agent: environment facts
  (folder, OS, how `bash` behaves) prevent more mistakes than a
  "15 years of experience" role line. That is our judgement, not the
  guide's.
