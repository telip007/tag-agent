---
title: OpenRouter SDK as a separate repo and submodule
summary: Published on its own, developed in place.
updated: 2026-10-17
---

# 0003 OpenRouter SDK as a separate repo and submodule

## Context

Tag Agent needs an OpenRouter client. A spec-generated, Swift 6,
multi-platform SDK is useful well beyond this project, so it should stand on
its own: its own repository, docs, wiki and community, with no knowledge of
Tag Agent.

## Decision

Build the SDK as its own public repository,
[telip007/swift-openrouter](https://github.com/telip007/swift-openrouter),
generated from OpenRouter's OpenAPI spec with a hand-written ergonomic layer.
Tag Agent includes it as a git submodule at `Packages/OpenRouter` and depends
on it by path, so both can change in one working tree. The SDK never
mentions Tag Agent.

## Consequences

- SDK changes are committed and pushed in the SDK repo before Tag's submodule
  pointer is bumped. See [OpenRouter SDK](../concepts/openrouter-sdk.md).
- The SDK carries its own backpressure setup and its own wiki.
- Once the SDK is tagged, Tag could switch to a versioned URL dependency.
  We keep the submodule while both evolve together.
