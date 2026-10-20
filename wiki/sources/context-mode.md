---
title: Context Mode
summary: Context Mode keeps tool payloads outside the prompt and retrieves exact excerpts; Tag can adopt the mechanisms without its MCP and hook layer.
updated: 2026-10-20
---

# Context Mode

Source: [mksglu/context-mode](https://github.com/mksglu/context-mode), read
2026-10-20 at `b31c7ee853cb9ea76121e24d368599390972a997` (`1.0.169`).
[Capture and pinned links](../raw/2026-10-20-context-mode.md).

## Mechanisms observed in code

- **Compute outside the prompt.** `src/executor.ts` executes programs in
  child processes. `src/server.ts` exposes execute, file execution and batch
  tools; intermediate data can stay inside the process and only selected
  output returns to the model. This is data-flow control, not inherently
  an OS sandbox. Arbitrary execution still inherits filesystem authority.
- **Externalize large results.** In `src/server.ts`, ordinary successful
  output over 102,400 bytes is indexed and replaced by a reference. An
  optional intent triggers indexing above 5,000 bytes; the initial reply
  gives matched titles/previews and terms for later searching. Error and
  timeout branches have their own handling; these thresholds are not a
  universal guarantee on every returned message.
- **Retrieve exact evidence.** `src/store.ts` uses SQLite FTS5 with Porter
  and trigram indexes, title-weighted BM25, reciprocal rank fusion,
  proximity reranking, then fuzzy correction when necessary. Markdown
  structure and plain-text sections inform chunking; a 4,096-byte chunk
  cap prevents oversized sections. File sources have hashes for freshness.
- **Batch acquisition and questions.** Batch tools collect and index
  several commands before answering several queries, avoiding a model
  round trip per intermediate result. Batch scope defaults to that batch.
- **Recover session state.** `src/session/extract.ts` derives events from
  host hooks; `db.ts` stores them and `snapshot.ts` assembles resume
  information plus retrieval queries. Snapshot assembly has no overall
  byte budget, despite limits on individual categories. Tag can capture
  its own typed events directly instead of parsing another host's tools.

The executor's 100 MiB hard capture cap is separate from prompt admission
limits. Likewise, bounded chunks do not guarantee a bounded aggregate
response. These distinctions matter for a native design.

## Claims and evidence boundaries

The pinned [benchmark](https://github.com/mksglu/context-mode/blob/b31c7ee853cb9ea76121e24d368599390972a997/BENCHMARK.md)
reports 376 KB to 16.5 KB overall (96%), with 98% for a structured-processing
subset and 82% for exact retrieval. Those are selected output-volume
comparisons. They do not establish coding success, recall completeness,
end-to-end billed-token savings or three-hour Tag sessions. We did not
rerun the benchmark. The
[metrics ADR](https://github.com/mksglu/context-mode/blob/b31c7ee853cb9ea76121e24d368599390972a997/docs/adr/0004-stats-strict-compression-formula.md)
also distinguishes per-conversation output accounting from stored-event
volume; Tag should report these separately.

The pinned [LICENSE](https://github.com/mksglu/context-mode/blob/b31c7ee853cb9ea76121e24d368599390972a997/LICENSE)
is Elastic License 2.0, with hosted-service restrictions and notice
requirements. Recommendation: write original Swift code around the
documented ideas and public SQLite capabilities. Any code reuse requires a
separate license assessment; this research does not settle that question.

## Relevance to Tag

Tag owns its [tool loop](../concepts/tools.md), so result admission can be
enforced in the harness across providers. MCP transport, client-specific
hooks, routing-denial prompts and a Node runtime are unnecessary for the
core design. [Paper research](agent-context-research.md) suggests additional
baselines and improvements. The
[historical proposal](../designs/native-context-management.md) led to the
[native implementation](../concepts/native-context.md) and
[decision 0016](../decisions/0016-native-context.md). Tag uses original Swift
code; the upstream benchmark figures remain upstream claims.
