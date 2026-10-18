---
title: OpenAI prompt engineering best practices
summary: OpenAI's short help-centre list of prompt rules: instructions first, delimiters, specifics, examples, say what to do.
updated: 2026-10-18
---

# OpenAI prompt engineering best practices

Raw capture: [raw/2026-10-18-openai-prompt-engineering.md](../raw/2026-10-18-openai-prompt-engineering.md).

## Summary

- Put instructions at the beginning and separate them from context with
  delimiters (`###`, `"""`).
- Be specific about context, outcome, length, format and style.
- Show the output format with an example. Start without examples, add a
  few only when needed.
- Replace vague words with exact ones: "3 to 5 sentences", not "fairly
  short".
- Say what to do instead of only what not to do. Their bad example is
  shouted (`DO NOT ASK USERNAME OR PASSWORD`); the good one describes the
  behaviour wanted and the alternative.

## How we use it

Rules 3, 5, 6 and 7 of the best practices in
[system prompt](../concepts/system-prompt.md). XML tags play the role of
the delimiters.
