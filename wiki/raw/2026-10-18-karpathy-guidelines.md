# Karpathy guidelines skill — capture

- URL: https://github.com/multica-ai/andrej-karpathy-skills/blob/main/skills/karpathy-guidelines/SKILL.md
- Captured: 2026-10-18
- MIT licence. This file holds excerpts and notes only.

## What it is

A Claude Code skill of "behavioral guidelines to reduce common LLM coding
mistakes", derived from a post by Andrej Karpathy on LLM coding pitfalls.
It says it biases "toward caution over speed". Four sections, each with a
bold slogan and a list of bullets.

## Excerpts

1. **Think Before Coding:** "State your assumptions explicitly. If
   uncertain, ask." "If multiple interpretations exist, present them -
   don't pick silently."
2. **Simplicity First:** "Minimum code that solves the problem. Nothing
   speculative." "No abstractions for single-use code." "If you write 200
   lines and it could be 50, rewrite it."
3. **Surgical Changes:** "Touch only what you must. Clean up only your own
   mess." "If you notice unrelated dead code, mention it - don't delete
   it." "Remove imports/variables/functions that YOUR changes made unused."
4. **Goal-Driven Execution:** turn tasks into verifiable goals ("Fix the
   bug" → "Write a test that reproduces it, then make it pass"), and state
   a short plan with a check per step for multi-step tasks.

## Notes

- Written as a skill loaded on demand, roughly 600 tokens, in an emphatic
  style (slogans, capitals in "YOUR", many "No …" bullets).
- Also uses a persona check: "Would a senior engineer say this is
  overcomplicated?"
