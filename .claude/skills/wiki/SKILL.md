---
name: wiki
description: Query, update, ingest into, or lint this repository's LLM-maintained wiki (wiki/). Use at the start of any task to find what the project already knows, after any change to code, configuration, tooling or decisions to record what changed and why, when the user shares an article/doc/link to file away, and when asked to health-check the wiki.
---

# Project wiki

`wiki/` is this project's compounding memory, following Karpathy's LLM-wiki
pattern. Agents write and maintain it; humans read it. The full conventions
are in `wiki/SCHEMA.md`. Read it once per session before editing the wiki.

## Query (before working)

1. Read `wiki/index.md` (it's also in your session context) and open every page
   that plausibly relates to the task.
2. Prefer what the wiki says over re-deriving it, but verify claims that name
   files, flags or APIs against the code. If the wiki is wrong, fix it.
3. When a question took real synthesis to answer, file the answer as a page.

## Update (after working)

For every change to code, config, tooling, dependencies or decisions:

1. Update the pages whose claims changed. Bump their `updated:` date.
2. Record **why**: new decisions go in `wiki/decisions/` (next free number),
   surprises and traps in the relevant concept page's "Gotchas" section.
3. New concept or component? Create a page, add it to `wiki/index.md`, and
   link it from at least one related page.
4. Append to `wiki/log.md`: `## [YYYY-MM-DD] update | <what changed>` plus 1–3
   lines. Never edit old log entries.
5. Run `make wiki-lint`.

Skip the update only when nothing a future reader would need changed (typo
fixes, pure formatting); say so explicitly.

## Ingest (user shares a source)

1. Save the source unchanged under `wiki/raw/` as
   `YYYY-MM-DD-<slug>.md` with the URL and capture date on top. Files in
   `raw/` are immutable (the pre-commit hook enforces it).
2. Discuss the key takeaways with the user.
3. Write `wiki/sources/<slug>.md` summarising it, then update every concept or
   decision page it confirms, extends or contradicts. Flag contradictions
   inline as `> **Contradiction:** …` instead of silently overwriting.
4. Update `wiki/index.md`, append `## [YYYY-MM-DD] ingest | <title>` to the log.

## Lint (health check)

Run `make wiki-lint` for structure, then read through and fix:
contradictions between pages, stale claims superseded by newer code or
sources, concepts mentioned without their own page, missing cross-links,
pages whose referenced files moved. Log it as `lint`.
