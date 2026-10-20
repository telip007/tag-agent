---
title: Bounded prompt research through the native Agent
summary: Evaluate prompts through an opt-in research bridge, preserve frozen evidence and retain baseline when replacement is unjustified.
updated: 2026-10-20
---

# 0014: Bounded prompt research through the native Agent

## Context

The request is to research prompt strategies and find a strong, efficient Tag
system prompt using benchmarks. A preferred next-action screen cannot establish
completed coding behavior. The broader production evaluation CLI remains a
roadmap; building it is not necessary for this research request. See the
[experiment design](../designs/prompt-optimization.md).

## Decision

Use a standard-library Python research supervisor and an opt-in Swift test
bridge over the actual Agent, adapters and built-in tools. Keep this work under
`Evals/prompt-lab/` and explicit benchmark tests; ordinary tests make no live
benchmark requests. Use synthetic fixtures, external functional checks, shared
call/token/time controls and separate development/reserved data.

Freeze prompt text, task definitions, sources and compiled bundle before
reserved requests. Retain failed outcomes and missing usage. Continue only
unrun cells after a verified terminal scheduling stop; do not retry failed cells
or tune prompts on reserved results while retaining their held-out label.
Keep immutable local raw traces outside Git when they contain process metadata;
retain manifests, source archives, hashes, audits and derived reports.

The completed experiment retains baseline/standard under the original
selection protocol because compact did not confirm a replacement advantage.
This preserves [decision 0009](0009-system-prompt.md), not a new claim of
universal optimality. The exact artifact, interpretation and verification are
in the [final report](../../Evals/prompt-lab/recommendation/FINAL.md).

## Consequences

The research exercises real tool execution without adding production CLI
evaluation flags, a new service or a production prompt replacement. A necessary
reasoning-history compatibility repair is covered by adapter regression tests.
Fixture directories are not an adversarial sandbox. Mutable model aliases,
finite authored tasks, exploratory intervals and incomplete usage limit claims;
local checks and read-only review do not imply release or publication.

All 812 main trajectories and 58 raw failures are traceable through the
[run and failure index](../../Evals/prompt-lab/results/main-failure-audit.json).
The overlapping 528-cell selection matrix is not counted as additional runs.
Future prompt revisions informed by these reserved results need new unseen
validation. A future public raw projection would preserve provenance and be
reviewed separately; historical raw records stay unchanged.
