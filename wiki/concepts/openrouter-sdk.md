---
title: OpenRouter SDK
summary: How Tag Agent consumes the swift-openrouter submodule and where its own docs live.
updated: 2026-10-17
---

# OpenRouter SDK

Tag Agent talks to models through
[swift-openrouter](https://github.com/telip007/swift-openrouter), checked out
as a git submodule at `Packages/OpenRouter` and referenced from
[Package.swift](../../Package.swift) with `.package(path:)`. Only the `TagKit`
library target depends on it ([0005](../decisions/0005-tag-and-tagkit-targets.md)). Why:
[0003](../decisions/0003-openrouter-sdk-submodule.md).

The SDK has its own wiki (`Packages/OpenRouter/wiki/`) covering the OpenAPI
generation pipeline, retries, streaming, errors and platform transports.
**Read it there; don't duplicate it here.** This page only records how Tag Agent
uses the SDK.

## Usage in Tag Agent

```swift
import OpenRouter

let openRouter = try OpenRouterClient.fromEnvironment(
    configuration: .init(appTitle: "Tag Agent")
)
```

`OPENROUTER_API_KEY` must be set. The submodule fetches over HTTPS (so
anyone can clone) and pushes over SSH. The SDK's README has the full tour:
`send`, `stream` + `ChatStreamAccumulator`, tool definitions, typed errors.

## Working on the SDK from Tag Agent

- Changes inside `Packages/OpenRouter` are commits in the SDK repo: commit and
  push there first, then commit the updated submodule pointer in Tag Agent.
- `make sdk-check` runs the SDK's own `make check`. `make check-all` runs both.
- After cloning Tag Agent, run `make bootstrap` (or `git submodule update --init`),
  otherwise `Packages/OpenRouter` is empty and the build fails.
