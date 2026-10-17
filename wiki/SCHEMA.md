# Wiki schema

How this wiki is organised and maintained. It follows Andrej Karpathy's
[LLM-wiki pattern](sources/llm-wiki-pattern.md): agents write and maintain the
wiki, humans curate sources and ask questions, and knowledge is compiled
once and kept current instead of being re-derived every session.

## Layers

| Path | What | Who writes |
| --- | --- | --- |
| `raw/` | Captured sources: notes and short excerpts of articles, docs, threads. **Immutable.** | Agent, on ingest |
| `sources/` | One summary page per raw source | Agent |
| `concepts/` | How things work: architecture, tooling, workflows, plus a **Gotchas** section | Agent |
| `decisions/` | Numbered decision records: context, decision, consequences | Agent, after human agrees |
| `index.md` | Catalog of every page with a one-line summary | Agent, on every change |
| `log.md` | Append-only timeline of ingests, updates, decisions, lints | Agent |

## Page format

Every page except `index.md`, `log.md` and this file starts with:

```yaml
---
title: Human-readable title
summary: One sentence; the same sentence goes in index.md
updated: YYYY-MM-DD
---
```

- Link generously with relative links: `[retries](../concepts/retries.md)`.
  Links to code (`../../Sources/...`) are checked too, so they break loudly
  when files move.
- State facts with their source: a file path, a decision record, or a
  `sources/` page. Mark guesses as guesses.
- Contradictions are flagged inline (`> **Contradiction:** …`) and resolved
  later. They are not silently overwritten.
- **The wiki is public.** It never contains personal information about
  contributors, references to unrelated projects, local machine details
  (absolute paths, usernames, hostnames) or email addresses. Use
  repository-relative paths. `wiki-lint` rejects home paths and emails.
- Copyrighted web content: `raw/` keeps the URL, the capture date, short
  quoted excerpts and our own notes. It never holds a full copy.

## Decision records

`decisions/NNNN-kebab-title.md` with sections **Context**, **Decision**,
**Consequences**. A superseded record is not deleted: add
`Superseded by [NNNN](NNNN-....md)` at the top.

## Log format

```text
## [YYYY-MM-DD] <ingest|update|decision|query|lint> | <title>
1–3 lines of detail.
```

`grep '^## \[' wiki/log.md | tail -5` shows recent activity.

## Enforcement

- `make wiki-lint` (also in pre-commit, `make check` and CI) checks frontmatter,
  index coverage, links and log format. With `--staged` it also rejects
  modifications to existing `raw/` files.
- Claude Code hooks (`.claude/settings.json`): the session start loads the
  index, and the Stop hook blocks ending a turn with code changes but no wiki
  changes.
- Workflows for querying, updating, ingesting and linting live in the `wiki`
  skill (`.claude/skills/wiki/SKILL.md`). Agents without skills follow
  `AGENTS.md`.
