---
title: Context Mode research capture
summary: Pinned upstream code and primary research sources for native context management in Tag.
updated: 2026-10-20
---

# Context Mode research capture

Captured: 2026-10-20. Source: <https://github.com/mksglu/context-mode>,
revision `b31c7ee853cb9ea76121e24d368599390972a997`, package version
`1.0.169`. Repository and selected implementation files were read; no
upstream installation scripts, hooks or benchmarks were executed.

This capture records links and research notes, not a copy of the repository.

- [Server](https://github.com/mksglu/context-mode/blob/b31c7ee853cb9ea76121e24d368599390972a997/src/server.ts): execution, indexing, intent queries and response limits.
- [Store](https://github.com/mksglu/context-mode/blob/b31c7ee853cb9ea76121e24d368599390972a997/src/store.ts): chunking, lexical indexes and ranking.
- [Executor](https://github.com/mksglu/context-mode/blob/b31c7ee853cb9ea76121e24d368599390972a997/src/executor.ts): subprocess lifecycle and bounded capture.
- [Session extraction](https://github.com/mksglu/context-mode/blob/b31c7ee853cb9ea76121e24d368599390972a997/src/session/extract.ts), [database](https://github.com/mksglu/context-mode/blob/b31c7ee853cb9ea76121e24d368599390972a997/src/session/db.ts) and [resume snapshot](https://github.com/mksglu/context-mode/blob/b31c7ee853cb9ea76121e24d368599390972a997/src/session/snapshot.ts).
- [Benchmark](https://github.com/mksglu/context-mode/blob/b31c7ee853cb9ea76121e24d368599390972a997/BENCHMARK.md), [metrics ADR](https://github.com/mksglu/context-mode/blob/b31c7ee853cb9ea76121e24d368599390972a997/docs/adr/0004-stats-strict-compression-formula.md), [license](https://github.com/mksglu/context-mode/blob/b31c7ee853cb9ea76121e24d368599390972a997/LICENSE).

Primary papers opened in full HTML or PDF, with versions fixed for citation:

- [CodeAct, 2402.01030v4](https://arxiv.org/html/2402.01030v4).
- [The Complexity Trap, 2508.21433v1](https://arxiv.org/html/2508.21433v1).
- [MemGPT, 2310.08560v1](https://arxiv.org/html/2310.08560v1).
- [ReWOO, 2305.18323v1](https://arxiv.org/html/2305.18323v1).
- [Context-Folding, 2510.11967v1](https://arxiv.org/pdf/2510.11967v1).
- [Recursive Language Models, 2512.24601v1](https://arxiv.org/html/2512.24601v1).
- [Agentic Context Engineering, 2510.04618v3](https://arxiv.org/html/2510.04618v3).
- [Agentic Context Management, 2607.23809v1](https://arxiv.org/html/2607.23809v1).
- [SQLite FTS5 documentation](https://www.sqlite.org/fts5.html).

Interpretation and limits: [source synthesis](../sources/context-mode.md),
[paper comparison](../sources/agent-context-research.md),
[Tag feasibility proposal](../designs/native-context-management.md).
