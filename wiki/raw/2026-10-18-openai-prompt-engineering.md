# Best practices for prompt engineering with the OpenAI API — capture

- URL: https://help.openai.com/en/articles/6654000-best-practices-for-prompt-engineering-with-the-openai-api
- Captured: 2026-10-18. The page is behind a bot check; it was read through
  a text reader that dropped the headings, so the rule names below are our
  paraphrase.
- Copyright belongs to OpenAI. This file holds excerpts and notes only.

## Excerpts

Separating instructions from context:

> Summarize the text below as a bullet point list of the most important
> points. Text: """{text input here}"""

Reducing imprecise descriptions:

> Use a 3 to 5 sentence paragraph to describe this product.

instead of "fairly short, a few sentences only, and not too much more".

Saying what to do instead of what not to do. The bad example:

> DO NOT ASK USERNAME OR PASSWORD. DO NOT REPEAT.

The better one:

> The agent will attempt to diagnose the problem and suggest a solution,
> whilst refraining from asking any questions related to PII. Instead of
> asking for PII, such as username or password, refer the user to the help
> article […]

## Notes

The article's rules, paraphrased:

1. Use the latest model.
2. Put instructions at the beginning; separate them from context with `###`
   or `"""`.
3. Be specific and detailed about context, outcome, length, format, style.
4. Show the output format with an example.
5. Start zero-shot, then few-shot, then fine-tune.
6. Replace fluffy descriptions with exact ones.
7. Say what to do, not only what not to do.
8. For code, use "leading words" (start the answer, e.g. `import`).
