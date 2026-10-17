---
title: LLM-maintained wiki
summary: Project memory lives in wiki/, enforced by hooks.
updated: 2026-10-17
---

# 0004 LLM-maintained wiki

## Context

Agent sessions start cold and rediscover the same facts: why a rule exists,
what broke last time, how the pieces fit. Chat history disappears.
[Karpathy's LLM-wiki pattern](../sources/llm-wiki-pattern.md) compiles that
knowledge once into interlinked markdown and keeps it current.

## Decision

Keep a wiki in `wiki/` following [SCHEMA.md](../SCHEMA.md), shared through git.
Agents maintain it. Enforcement is layered so it doesn't depend on any agent
remembering (details in [Agent workflow](../concepts/agent-workflow.md)):
session-start context injection, a Stop hook that blocks finishing without
wiki updates, a `wiki` skill, a structural linter in pre-commit,
`make check` and CI.

## Consequences

- Every non-trivial change produces a log entry and, where relevant,
  updated concept or decision pages.
- The index is the retrieval mechanism. If it outgrows a single file, add
  search (e.g. qmd, as suggested in the source) and record that here.
