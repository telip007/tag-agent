# pi coding agent system prompt — capture

- URL: https://github.com/earendil-works/pi
- Files read: `packages/coding-agent/src/core/system-prompt.ts`,
  `packages/coding-agent/src/core/tools/{read,bash,edit,write}.ts`
- Captured: 2026-10-18
- MIT licence. This file holds excerpts and notes only.

## Excerpts

Default preamble:

> You are an expert coding assistant operating inside pi, a coding agent
> harness. You help users by reading files, executing commands, editing
> code, and writing new files.

Rules that are always added:

> Be concise in your responses

> Show file paths clearly when working with files

Rule added when there is a shell but no search tools:

> Use bash for file operations like ls, rg, find

Per-tool contributions:

> read — snippet: "Read file contents", guideline: "Use read to examine
> files instead of cat or sed."

> write — snippet: "Create or overwrite files", guideline: "Use write only
> for new files or complete rewrites."

Project files:

> `<project_instructions path="${path}">\n${content}\n</project_instructions>`

Bash tool description:

> Output is truncated to last N lines or N KB (whichever is hit first). If
> truncated, full output is saved to a temp file. Optionally provide a
> timeout in seconds.

## Notes

- The prompt is a record of named sections in this order: `preamble`
  (untagged), `tools`, `rules`, `docs`, `addendum`, `project_context`,
  `skills`, `cwd`, then custom sections. Every section except the preamble
  is wrapped in an XML tag of its own name.
- Rules are assembled from the active tools' guidelines and deduplicated, so
  removing a tool removes its rules.
- `diffSystemPromptSections` produces a patch of changed sections, so a
  running session can update one section without resending the prompt.
- Tool results carry `truncated`, `full_output_path`, `exit_code` and
  `wall_time_seconds`.
