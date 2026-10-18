---
title: System prompt
summary: Tag sends a short system prompt built in Swift from sections, with tool rules on each ToolDefinition, a probed environment and AGENTS.md; the date rides on user messages.
updated: 2026-10-18
---

# 0009 System prompt

## Context

Until now `Agent` sent no system message: the model didn't know the folder,
the OS, how `bash` behaves or the project's own rules.
[System prompt](../concepts/system-prompt.md) collected best practices from
four sources and left six open questions.

## Decision

Answers to the open questions, for a first version:

1. **Length: short.** The draft's five general rules plus one line per tool
   rule. (Six since a simplicity rule was added from the
   [Karpathy guidelines](../sources/karpathy-guidelines.md), which also
   extended the change and ask rules.) A longer workflow gets added when a model gets something wrong, one
   change at a time.
2. **Autonomy: run until done**, asking before destructive or outward-facing
   actions and when the request is ambiguous.
3. **Built in Swift from sections** (`SystemPrompt.render`), not a resource
   template. Each `ToolDefinition` carries a `summary` for the tool list and
   `guidelines` for the rules, so removing a tool removes its rules.
4. **Project instructions: only `AGENTS.md` in the working directory,**
   verbatim in `<project_instructions path="AGENTS.md">`. Parent folders and
   a user-level file can come later.
5. **Identity: "Tag".**
6. **No git status.** Only "Git repository: yes/no". Branch and status change
   during a session, and a messy tree would cost tokens on every request.

Everything else follows the page's best practices: static sections first,
the environment probed once at startup (`SessionEnvironment.probe`) and
rendered last, the prompt rendered once per session and never changed. The
date is not in the system prompt: `UserMessageDater` puts
`<environment_update>date: …</environment_update>` before the first user
message and before any message sent after the date changed.

## Consequences

- `Agent` takes a `SessionEnvironment` instead of a bare working directory,
  plus an injectable clock; tests use a fake environment and a snapshot of
  the rendered prompt.
- Every request now starts with the same system message, which also gives
  OpenRouter's sticky routing a stable key (see
  [prompt caching](../concepts/prompt-caching.md)).
- The user's message text in the conversation can differ from what the UI
  shows (the date note); the UI gets its text from `ChatSession`, not from
  the conversation.
