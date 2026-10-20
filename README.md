<p align="center">
  <img src=".github/assets/banner.png" alt="Tag Agent: a coding-agent harness for the terminal, written in Swift" width="100%">
</p>

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

You pick the model. Tag talks to your **ChatGPT plan** (Codex models, through
OpenAI's Sign in with ChatGPT), an **OpenCode Go** subscription, or
**OpenRouter** (through
[swift-openrouter](https://github.com/telip007/swift-openrouter), a git
submodule in `Packages/OpenRouter`). The first start walks you through
connecting a provider and choosing a model. Each launch starts a new session,
using your last selected model and reasoning effort. Resume a saved conversation
explicitly with `tag --resume <id>`. `/model` opens a searchable picker,
and `/model <provider>/<model>` (for example `/model go/kimi-k3`) switches
straight away while keeping the conversation. The system prompt gives the
model the tools, the working directory and the project's `AGENTS.md` if
there is one.

> Status: early. The harness is being built step by step.

<img src=".github/assets/logo.png" alt="" width="96" align="right">

The mascot is a tabby street cat in a fez, drawn as pixel art. It greets you
in an empty conversation, and the same sprite draws the logo and the banner
(`swift .github/assets/render-assets.swift`).

## Tools

| Tool | What it does |
| --- | --- |
| `read_file` | read a text file |
| `list_files` | list a directory recursively (hidden entries skipped) |
| `edit_file` | replace one exact match in a file, or create a file |
| `bash` | run a shell command in the working directory |
| `code_search` | search with [ripgrep](https://github.com/BurntSushi/ripgrep) |
| `read_output`, `search_output` | read exact ranges or find cited excerpts in retained session evidence |
| `index_file`, `fetch_and_index` | retain bounded UTF-8 file or HTTP snapshots |
| `analyze_output` | process an entire retained artifact through the installed shell using stdin |
| `batch_execute` | capture ordered commands and answer queries within that batch |
| `read_history`, `search_history` | retrieve canonical events from the active session |
| `context_stats`, `context_doctor` | inspect measured volumes and read-only integrity checks |

Session-backed tools retain large, failed or partial results before showing a
bounded preview. Search finds selected evidence; whole-input analysis supplies
all retained bytes to the command. Capture quotas and deadlines remain explicit.
Use `index_file` then `analyze_output` to process a file without putting it in
the prompt. Python, JavaScript or other installed interpreters can be invoked
through the existing shell. See [native context](wiki/concepts/native-context.md)
for limits and the [deterministic evaluation](wiki/designs/native-context-evaluation.md).

> [!WARNING]
> The agent edits files and runs shell commands in the directory you start it
> in, without asking first. Use it in a directory under version control.

## The terminal UI

Tag runs full screen, with [Stipple](https://github.com/telip007/stipple). The
conversation fills the left pane: your messages, replies, tool calls grouped
into trays you can expand, and every file edit as a small diff. The panel on
the right shows the model, how full its context window is, cache reads and
writes reported for the latest completed reply, what the session has cost, how long
it has run, and which files changed. Missing cache metrics are omitted;
reported zeros are shown. See [prompt caching](wiki/concepts/prompt-caching.md)
for the provider policies and limits.

| Key | What |
| --- | --- |
| Enter | send; while the agent works, queue the message (type-ahead) |
| Ctrl-O, `/sessions` | search, preview and select saved sessions |
| `/new`, `/clear` | create a session, keeping the previous history |
| `/reference` | preview and attach excerpts from another session |
| `/compact` | shorten the model context, preserving full history and exact retrieval |
| `/compact off` | restore the full model context |
| `/context` | show retained bytes, presented output bytes and last provider usage |
| `/context doctor` | check history, evidence and indexes without changing data |
| `/context off` | hide the local context report |
| ↑ / ↓ | recall sent messages; ↓ past the newest restores your draft |
| Esc | browse the conversation: ↑↓ to move, Enter to expand, c to copy |
| Page Up / Down | scroll the conversation |
| Ctrl-P | commands for models, sessions, references, browsing and quitting |
| Tab | show or hide the session panel |
| Ctrl-C | clear the line; on an empty line, press twice to quit |
| Ctrl-D | quit, on an empty line |

The mouse works too: the wheel scrolls, a click expands a tool tray or a diff,
and the hints in the footer are buttons. To select text with the mouse, hold
Shift (Option in some macOS terminals).

Plain `tag` always starts a new session; `tag --new` is an explicit equivalent.
Use `tag --resume <id>` to open a saved session by full ID or unique prefix,
or select one in the session navigator. Workspaces, including sibling worktrees,
remain distinct. Opening a saved session waits for your next message. The session picker preserves drafts and offers title/content
search, a conversation preview, Tab for all workspaces and Ctrl-R to rename.
Explicit references are copied, bounded and cited; the agent has no automatic discovery of other
sessions. Native history search stays inside the active session. See [session storage](wiki/concepts/session-storage.md).

Input needs an interactive terminal; piping messages on stdin is not
supported.

## Setup

```sh
git clone --recurse-submodules https://github.com/telip007/tag-agent.git
cd tag-agent
make bootstrap   # SwiftLint, ripgrep, git hooks, submodule
make run         # swift run -c release Tag
```

The first start asks you to connect a provider: sign in with ChatGPT in the
browser, or paste an OpenCode Go or OpenRouter API key. Keys can also come
from `OPENCODE_API_KEY` and `OPENROUTER_API_KEY`. Credentials and settings
are kept in `~/.config/tag/` (`$XDG_CONFIG_HOME/tag` or `$TAG_CONFIG_DIR`
when set), readable only by you. Session history and private backups live in
the `sessions/` subdirectory, separate from provider credentials.

Run the optimised build: a debug build (`swift run Tag`) draws several
times slower, which shows when resizing a long session.

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
