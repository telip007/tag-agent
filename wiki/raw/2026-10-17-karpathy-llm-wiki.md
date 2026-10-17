# LLM Wiki (Andrej Karpathy) — capture

- URL: https://gist.githubusercontent.com/karpathy/442a6bf555914893e9891c11519de94f/raw/ac46de1ad27f92b28ac95459c782c07f6b8c964a/llm-wiki.md
- Captured: 2026-10-17
- Copyright belongs to the author. This file holds excerpts and notes only.

## Excerpts

> Instead of just retrieving from raw documents at query time, the LLM
> incrementally builds and maintains a persistent wiki

> You never (or rarely) write the wiki yourself — the LLM writes and
> maintains all of it.

> There are three layers: Raw sources … The wiki … The schema

> Operations: Ingest … Query … Lint

> index.md is content-oriented … log.md is chronological … append-only

> Humans abandon wikis because the maintenance burden grows faster than the
> value.
