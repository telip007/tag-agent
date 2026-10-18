---
title: Karpathy guidelines
summary: A skill of four rules against common LLM coding mistakes (think first, keep it simple, change surgically, verify against goals), and which of them Tag's system prompt took.
updated: 2026-10-18
---

# Karpathy guidelines

Raw capture: [raw/2026-10-18-karpathy-guidelines.md](../raw/2026-10-18-karpathy-guidelines.md).

## Summary

A Claude Code skill (MIT) based on Andrej Karpathy's notes on LLM coding
pitfalls. Four rules: surface assumptions and ask instead of guessing; write
the minimum code, with nothing speculative; touch only what the task needs
and clean up only your own leftovers; turn tasks into checkable goals and
loop until they pass.

## What Tag took

Compared with the [system prompt](../concepts/system-prompt.md) rules:

| Guideline | In Tag |
| --- | --- |
| Simplicity first | **Added** as a rule: the simplest code, no features, abstractions or options nobody asked for. Over-building was the one gap. |
| Surgical changes | Already there ("change only what the task needs"); **added** "mention unrelated problems instead of fixing them; remove only what your own change left unused". |
| Think before coding | Already there (ask when ambiguous); **sharpened** to "name the readings and ask instead of picking one silently". |
| Goal-driven execution | Already there (run the build or tests after changing code). The reproduce-with-a-test-first step is left out: not every project has tests. |

Left out on purpose: the emphatic style (slogans, "YOUR", stacks of "No …"),
which goes against the prompt's "short, specific, calm" practice; the
"senior engineer" persona check; the plan template (a fixed format, added
only once a model needs it); and a general "stop and ask", which would work
against [0009](../decisions/0009-system-prompt.md)'s "run until done".
