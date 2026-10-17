# Tag Agent

A coding-agent harness for the terminal, written in Swift, and written by hand
to learn how coding agents actually work: the loop, tools, context and
streaming.

Models are accessed through OpenRouter via
[swift-openrouter](https://github.com/telip007/swift-openrouter) (a git
submodule in `Packages/OpenRouter`).

> Status: early. The harness is being built step by step.

## Setup

```sh
git clone --recurse-submodules <this repo>
cd tag-agent
make bootstrap                      # SwiftLint, git hooks, submodule
export OPENROUTER_API_KEY=sk-or-... # https://openrouter.ai/keys
swift run Tag
```

Requires Swift 6.2+ (Xcode 26) and macOS 15+.

## Development

`make check` runs everything CI runs: wiki lint, swift-format, SwiftLint, a
build with all warnings as errors, and tests with a coverage gate. The
reasoning behind this setup and every decision so far lives in the project
wiki: start at [wiki/index.md](wiki/index.md).

Working with a coding agent? See [AGENTS.md](AGENTS.md). Agents here review
and explain; the harness code itself is written by hand.
