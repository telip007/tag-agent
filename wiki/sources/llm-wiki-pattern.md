---
title: LLM wiki pattern
summary: Karpathy's idea file for agent-maintained knowledge bases.
updated: 2026-10-17
---

# LLM wiki pattern

Raw capture: [raw/2026-10-17-karpathy-llm-wiki.md](../raw/2026-10-17-karpathy-llm-wiki.md).

## Summary

- RAG re-derives knowledge on every question. An LLM-maintained wiki
  **compiles** it once and keeps it current, so it compounds.
- Three layers: immutable **raw sources**, the LLM-owned **wiki**, and a
  **schema** (CLAUDE.md/AGENTS.md) that makes the LLM a disciplined
  maintainer.
- Operations: **ingest** (one source can touch 10–15 pages), **query**
  (good answers are filed back as pages), **lint** (contradictions, stale
  claims, orphans, missing links).
- `index.md` (catalog, read first) and `log.md` (append-only, greppable
  prefixes) are enough navigation up to a few hundred pages.
- Humans abandon wikis because maintenance grows faster than value. LLMs make
  maintenance nearly free.

## How we applied it

- [SCHEMA.md](../SCHEMA.md) instantiates the pattern for a code repository: `concepts/`
  and `decisions/` replace entity pages, and code paths are linked and
  link-checked.
- Enforcement through hooks and skills: [Agent workflow](../concepts/agent-workflow.md).
