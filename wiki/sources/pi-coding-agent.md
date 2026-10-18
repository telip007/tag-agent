---
title: pi coding agent
summary: How the pi coding agent builds its system prompt from named, tagged sections with rules contributed by each tool.
updated: 2026-10-18
---

# pi coding agent

Raw capture: [raw/2026-10-18-pi-system-prompt.md](../raw/2026-10-18-pi-system-prompt.md).

## Summary

pi (earendil-works/pi) is an agent toolkit with a coding-agent CLI. Its
system prompt is built in code (`system-prompt.ts`):

- **Named sections, each in an XML tag:** a one-line preamble, then
  `<tools>`, `<rules>`, `<docs>`, `<project_context>`, `<skills>`, `<cwd>`.
- **Tools contribute their own prompt text:** a one-line snippet for the
  tool list and guideline bullets for the rules (e.g. "Use read to examine
  files instead of cat or sed"). Rules are deduplicated; drop a tool and its
  rules go too.
- **Very short base rules,** ending with "Be concise" and "Show file paths
  clearly".
- **Project files verbatim** as `<project_instructions path="…">`.
- **Live updates by section:** a diff of changed sections can be sent
  mid-session.
- **Tool limits live in tool descriptions,** not the prompt: truncation
  sizes, the temp file with the full output, the optional timeout.

## How we use it

The structure is the model for Tag's prompt in
[system prompt](../concepts/system-prompt.md): static tagged sections first,
per-tool rules on `ToolDefinition`, project instructions and the session
environment last. The temp-file truncation is item 3 in
[mini-swe-agent](mini-swe-agent.md).
