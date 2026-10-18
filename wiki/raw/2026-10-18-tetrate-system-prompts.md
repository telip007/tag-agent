# System Prompts: Design Patterns and Best Practices — capture

- URL: https://tetrate.io/learn/ai/system-prompts-guide
- Captured: 2026-10-18
- Copyright belongs to Tetrate. This file holds excerpts and notes only.

## Excerpts

> Because system prompts persist throughout a conversation, they consume
> tokens in every API call.

> Instead of "You are a helpful assistant," consider "You are a technical
> documentation specialist with expertise in API design and developer
> experience."

> Clear boundary statements help the model provide honest, accurate
> responses about its limitations rather than generating plausible-sounding
> but incorrect information.

> When modifying prompts, change one element at a time when possible.

> Treat system prompts as living documentation that requires periodic
> review and refinement rather than one-time configuration.

## Notes

- Components: role and identity, communication style, output format,
  knowledge boundaries, behavioural guidelines and constraints.
- Patterns: Specialist, Structured Output, Conversational Guide,
  Safety-First, Adaptive Complexity.
- Testing: evaluation criteria that are measurable; a test set of typical,
  boundary, adversarial, ambiguous and format-breaking cases (50–100 for
  production); fixed model and parameters; one change at a time; record why.
- Dynamic prompts: context-aware, personalised, task-specific injection,
  prompt chaining, dynamic constraints.
