---
title: System prompt
summary: How Tag's system prompt is built (sections in Swift, tool rules on each tool, a probed environment, AGENTS.md, the date on user messages) and the best practices behind it.
updated: 2026-10-18
---

# System prompt

Status: **built** on 2026-10-18, decided in
[0009](../decisions/0009-system-prompt.md).

## How it works

- [SystemPrompt.swift](../../Sources/TagKit/SystemPrompt.swift) renders the
  prompt from sections: an identity line, `<tools>` (each tool's `summary`),
  `<rules>` (general rules, then each tool's `guidelines`), `<environment>`
  and `<project_instructions path="AGENTS.md">` when that file exists.
- `SessionEnvironment.probe` runs once at startup in `Tag.swift`: folder,
  OS and version, architecture, `bash`'s `$BASH_VERSION` (the shell the
  `bash` tool really runs), `git rev-parse --is-inside-work-tree`, and
  `AGENTS.md`. A failed probe falls back (`bash`, "no") instead of failing.
- `Agent.run` renders the prompt once, after fetching the model's display
  name, and keeps it as the first message for the whole session.
- `UserMessageDater` prefixes the first user message, and any message sent
  after the local date changed, with
  `<environment_update>date: yyyy-MM-dd</environment_update>`.
- Tests: a snapshot of the rendered prompt with a fake environment
  (`SystemPromptTests`), the prompt staying identical across requests and
  the date notes (`AgentTests`), and a probe of a temporary folder.

The sections below are the research the first version was built from.

Sources: [mini-swe-agent](../sources/mini-swe-agent.md),
[OpenAI best practices](../sources/openai-prompt-engineering.md),
[Tetrate guide](../sources/tetrate-system-prompts.md),
[pi](../sources/pi-coding-agent.md). Rules on simplicity, unrelated
problems and ambiguous requests were added later from the
[Karpathy guidelines](../sources/karpathy-guidelines.md).

## Best practices

1. **Short, specific, calm.** Closer to pi (a handful of rules) than to
   mini (long, written for unattended benchmark runs). No capitals,
   `CRITICAL` or `MUST` (OpenAI's own example shows the shouted version as
   the bad one; recent models overreact to shouting).
2. **Describe the environment, not a persona.** Folder, OS, shell, date, how
   `bash` behaves, no stdin. These prevent real mistakes (`sed -i` on
   macOS, a `cd` that doesn't carry over); a role line doesn't.
3. **One XML tag per section** (mini and pi; OpenAI's delimiters).
4. **Tool guidance with the tools.** Descriptions say what a tool does and
   its limits; the prompt says when to use which. Each `ToolDefinition`
   should contribute its own rule lines, as in pi, so removing a tool
   removes its rules.
5. **Static parts first, session parts last,** so the static part is a
   cacheable prefix across sessions (see
   [prompt caching](prompt-caching.md)).
6. **Say what to do.** "Ask before deleting files outside the project", not
   "NEVER delete".
7. **Exact numbers instead of vague words,** e.g. the length of the final
   summary.
8. **A light workflow for an interactive agent:** read before editing,
   verify after changing, ask when unsure. mini's five steps (explore,
   reproduce, fix, re-run, edge cases) assume an unattended bug fix.
9. **Few examples,** only where a format matters. Start with none; add one
   when a model gets something wrong.
10. **Project instructions verbatim:** `AGENTS.md` as
    `<project_instructions path="AGENTS.md">`.
11. **Version and test the prompt:** a snapshot test of the rendered
    prompt; later an evaluation set (needs a headless mode and saved
    conversations, see [mini-swe-agent](../sources/mini-swe-agent.md));
    one change at a time, with the reason recorded.

What doesn't transfer from mini: "every reply MUST include a tool call" and
the submit command. In Tag a reply without tool calls is how a turn ends.

## The environment part is built at runtime

The prompt must not contain values typed in by hand. Two kinds of data:

**Fixed for the session.** Probe once at startup, render into the system
prompt, never change it during the session (that keeps the cache valid):

- working directory (Tag already has `workingDirectory`)
- OS, version, architecture (`ProcessInfo`, `uname`)
- the shell the `bash` tool really runs (not the user's `$SHELL`)
- model name (already fetched for the status line)
- git repository or not, default branch
- `AGENTS.md`
- OS-dependent rules: the `sed -i ''` rule only on macOS (mini uses
  `{% if system == "Darwin" %}`)

**Changes during the session.** Keep out of the system prompt; rewriting it
would invalidate the cache and the model would no longer see a linear
history:

- date (a session can cross midnight), git branch and status, context
  used, cost
- either a labelled snapshot at startup ("git status at the start of the
  session; it won't update"), or a short note on the next user message
  when something changed (`<environment_update>date: …</environment_update>`).
  pi sends changed sections as a diff.

Build the environment block in code from an injected value, so a test can
use a fake environment and snapshot the rendered prompt.

## Draft

The draft the first version was built from. The shipped prompt differs:
tool rules come from the tools, the environment lists shell and model on
their own lines, and the `bash` rule also says to chain with `&&`.

```text
You are Tag, a coding agent in the user's terminal. You help with software
tasks in one project: you read and search its code, run commands and edit files.

<tools>
- read_file: read a file
- list_files: list a folder
- code_search: search file contents (ripgrep)
- edit_file: replace one exact, unique snippet, or create a file
- bash: run a command in the project folder
</tools>

<rules>
- Read the relevant code before changing it. Use code_search to find things.
- Each bash call is a fresh shell in the project folder with no input:
  cd and export don't carry over, so use non-interactive flags.
- Change only what the task needs; match the surrounding code's style.
- After changing code, run the project's build or tests and read the result.
  If you couldn't, say so.
- Ask before destructive or outward-facing actions (deleting files,
  git push, anything outside the project), and when the request is ambiguous.
- Finish with 2–4 sentences: what changed, how you checked it, what's left.
  Name files by path.
</rules>

<environment>
macOS 26 (arm64): use `sed -i ''`. Folder: ~/code/project. Git: yes, branch main.
</environment>

<project_instructions path="AGENTS.md">
…
</project_instructions>
```

## Open questions

Answered for the first version in
[0009](../decisions/0009-system-prompt.md): short, run until done, Swift
sections, only `AGENTS.md`, "Tag", no git status. Revisit them when a model
misbehaves.

1. **Length:** minimal like pi, or spell out a workflow like mini because
   the default model (DeepSeek Flash) is weaker?
2. **Autonomy:** run until done, or check in before edits?
3. **Where it lives:** a resource file (`.md` template), or built in Swift
   from sections like pi, with tool rules on `ToolDefinition`?
4. **Project instructions:** only `AGENTS.md` in the working directory, or
   also parent folders and a user-level file?
5. **Identity:** call it "Tag" or no name?
6. **Git snapshot:** include `git status` at startup? Useful for
   orientation, but a messy tree costs tokens on every request.
