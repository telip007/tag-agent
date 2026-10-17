# Tag Agent

[![CI](https://github.com/telip007/tag-agent/actions/workflows/ci.yml/badge.svg)](https://github.com/telip007/tag-agent/actions/workflows/ci.yml)
![Swift 6.2+](https://img.shields.io/badge/Swift-6.2+-F05138)
![macOS 15+](https://img.shields.io/badge/macOS-15+-lightgrey)
[![Apache 2.0](https://img.shields.io/badge/license-Apache%202.0-blue)](LICENSE)

A coding-agent harness for the terminal, written in Swift, to learn how coding
agents actually work: the loop, tools, context and streaming.

It started as a Swift port of Thorsten Ball's
[How to build an agent](https://ampcode.com/notes/how-to-build-an-agent):
the first chat loop was written by hand, everything since by coding agents
under strict automated checks (see [the decisions](wiki/index.md#decisions)).

Models are accessed through OpenRouter via
[swift-openrouter](https://github.com/telip007/swift-openrouter) (a git
submodule in `Packages/OpenRouter`).

> Status: early. The harness is being built step by step.

## Tools

| Tool | What it does |
| --- | --- |
| `read_file` | read a text file |
| `list_files` | list a directory recursively (hidden entries skipped) |
| `edit_file` | replace one exact match in a file, or create a file |
| `bash` | run a shell command in the working directory |
| `code_search` | search with [ripgrep](https://github.com/BurntSushi/ripgrep) |

> [!WARNING]
> The agent edits files and runs shell commands in the directory you start it
> in, without asking first. Use it in a directory under version control.

## Setup

```sh
git clone --recurse-submodules https://github.com/telip007/tag-agent.git
cd tag-agent
make bootstrap                      # SwiftLint, ripgrep, git hooks, submodule
export OPENROUTER_API_KEY=sk-or-... # https://openrouter.ai/keys
swift run Tag
```

Requires Swift 6.2+ (Xcode 26) and macOS 15+.

## Development

`make check` runs everything CI runs: wiki lint, swift-format, SwiftLint, a
build with all warnings as errors, and tests with a coverage gate. The
reasoning behind this setup and every decision so far lives in the project
wiki: start at [wiki/index.md](wiki/index.md).

Working with a coding agent? See [AGENTS.md](AGENTS.md). Contributing? See
[CONTRIBUTING.md](CONTRIBUTING.md).

## License

[Apache 2.0](LICENSE).
