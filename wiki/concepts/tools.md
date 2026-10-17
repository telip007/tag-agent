---
title: Agent loop and tools
summary: How the agent loop runs tool calls, the five built-in tools, and where they differ from their Go originals.
updated: 2026-10-18
---

# Agent loop and tools

Tag Agent follows Thorsten Ball's "How to build an agent" (ampcode.com/notes),
ported from Go and the Anthropic API to Swift and the
[OpenRouter SDK](openrouter-sdk.md). The maintainer wrote the chat loop by hand
([0001](../decisions/0001-hand-written-agent-code.md)); the tool part was built
by an agent ([0006](../decisions/0006-agents-build-the-harness.md)).

## The loop

[Agent.swift](../../Sources/TagKit/Agent.swift):

1. If `readUserInput` is set, print `You:` and read a line (`nil` ends the
   session). Append it as a user message.
2. Send the whole conversation plus the tool definitions to the
   [`ChatModel`](../../Sources/TagKit/ChatModel.swift). Append the assistant
   message as returned (text, tool calls and any reasoning fields).
3. Print the text, if any.
4. Run every tool call in order and append each result as a `tool` message
   with the call's `id`.
5. If there were tool calls, clear `readUserInput` so the model sees the
   results straight away; otherwise ask the user again.

The agent is just this loop: the model decides which tools to call and when to
stop. A tool is a name, a description, a JSON Schema and a function from raw
JSON input to a string ([ToolDefinition.swift](../../Sources/TagKit/ToolDefinition.swift)).

Errors never end the session. An unknown tool, invalid JSON input or a thrown
error becomes the tool result (`error: …`), so the model can read it and try
again. OpenAI-style tool messages have no `is_error` flag, unlike Anthropic's
`tool_result`, so the `error:` prefix is the only signal.

Output goes through an injected `output` closure and input through
`getUserMessage`, so [the tests](../../Tests/TagKitTests/AgentTests.swift) drive
the loop with a scripted model and capture what the user would see.

## The file tools

[FileTools.swift](../../Sources/TagKit/FileTools.swift). The descriptions and
schemas match the tutorial word for word. Relative paths resolve against the
working directory the CLI was started in.

| Tool | Input | Output |
| --- | --- | --- |
| `read_file` | `path` | file contents (UTF-8) |
| `list_files` | optional `path` (default `.`) | JSON array of relative paths, directories end in `/` |
| `edit_file` | `path`, `old_str`, `new_str` | `OK`, or `Successfully created file <path>` |

### Where they differ from the Go originals

- **`edit_file` needs exactly one match.** The Go code replaces every
  occurrence even though its own schema says "must only have one match". We
  follow the schema and report how many matches there were, so the model adds
  context.
- **Empty `old_str` only creates files.** In Go, an empty `old_str` on an
  existing file inserts `new_str` between every character
  (`strings.Replace` semantics). We reject it.
- **`list_files` skips hidden entries** (`.git`, `.build`, `.swiftpm`). The
  Go version lists everything; in this repository that is tens of thousands of
  build files and fills the context window. Output is sorted.
- **Bad input is an error result, not a crash.** Go panics on invalid JSON.
  An empty arguments string is read as `{}` (some models send that for
  tools without required arguments).

## The shell tools

[ShellTools.swift](../../Sources/TagKit/ShellTools.swift) adds the two tools
from Geoffrey Huntley's workshop version of the tutorial
(github.com/ghuntley/how-to-build-a-coding-agent), again with its descriptions
and schemas word for word. With them the set matches the workshop: read, list,
edit, bash, code search.

| Tool | Input | Output |
| --- | --- | --- |
| `bash` | `command` | trimmed output (stdout and stderr merged); on a non-zero exit `Command failed with exit code N` plus the output |
| `code_search` | `pattern`, optional `path`, `file_type`, `case_sensitive` | `rg --line-number --with-filename` lines, at most 50, or `No matches found` |

Processes run through [swift-subprocess](https://github.com/swiftlang/swift-subprocess)
([ProcessRunner.swift](../../Sources/TagKit/ProcessRunner.swift)): it drains
stdout and stderr concurrently without blocking threads, merges them with
`.combinedWithOutput`, and enforces an output limit. Foundation's `Process`
needs all of that by hand. An earlier hand-rolled version blocked a thread per
pipe.

Differences from the Go originals:

- **Standard input is empty.** The agent reads the user's messages from its
  own stdin; in Go a command like `cat` would swallow them.
- **Output is capped at 1 MB** per run. Beyond that the tool returns an error
  telling the model to narrow the command (`head`, `grep`). Go has no limit.
- **`code_search` passes `--` before the pattern**, so a pattern starting with
  `-` isn't read as an option, and it searches in the working directory, not
  wherever the process happens to be.
- A missing program (`rg is not installed`) or a ripgrep error (exit 2,
  with its stderr) becomes an error result.

### Where ripgrep comes from

ripgrep must be on `PATH`; `make bootstrap` and CI install it with Homebrew.
The test that runs the real `rg` is skipped when it isn't installed; the other
search tests use `echo` as a stand-in (`codeSearch(workingDirectory:ripgrep:)`).
Options for later, when Tag ships as a binary: a Homebrew formula with
`depends_on "ripgrep"`, bundling `rg` next to the executable (as Claude Code
and VS Code do), or a `grep -rn` fallback. SwiftPM artifact bundles can't do
it: their executables are only available to build plugins, not at runtime.

## Gotchas

- **`MemberImportVisibility` and JSON literals.** Writing a schema as a
  `[String: JSONValue]` literal needs `import OpenRouter` in that file, even
  though `TagKit` already imports it elsewhere: the literal initialisers are
  members of a type from that module. The same goes for `localizedDescription`
  (needs `import Foundation`) and for test files, whose target therefore
  depends on the `OpenRouter` product explicitly.
- **`strictMemorySafety` flags `FileManager.fileExists(atPath:isDirectory:)`**
  because of its `inout ObjCBool` pointer. Use
  `URL.resourceValues(forKeys: [.isDirectoryKey])` instead.
- **Name clash with swift-subprocess.** Its module and its `run` function
  are both called `Subprocess`, so a local type of that name hides the
  module's `Subprocess.run`. Ours is `ProcessRunner`.
- **swift-subprocess throws on too much output** (`outputLimitExceeded`)
  instead of truncating. `ProcessRunner` maps that to a tool error.
- **`ChatFunctionTool.value1` is optional** in the generated code (it is a
  `oneOf` wrapper), so reading a tool's name back needs `value1?.function.name`.
