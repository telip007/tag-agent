---
title: mini-swe-agent
summary: The SWE-bench team's ~100-line, bash-only agent that scores >74% on SWE-bench Verified, and what Tag can borrow from it.
updated: 2026-10-18
---

# mini-swe-agent

Raw capture: [raw/2026-10-18-mini-swe-agent.md](../raw/2026-10-18-mini-swe-agent.md).

## Summary

mini-swe-agent scores well because the scaffold does almost nothing, so the
model's own ability decides the result:

- **Bash is the only tool.** Models know the shell from training data;
  custom tools are quirks to learn and ways to fail.
- **Every command is a fresh subprocess** with a timeout that kills the
  process group. No persistent shell, so no hung sessions, stale `cd` or
  output that never ends. Swapping in `docker exec` is the whole sandbox.
- **Linear history.** Each step appends; nothing is summarised or
  rewritten. The trajectory is exactly what the model saw, and one cache
  marker on the last message is enough for Anthropic caching.
- **Clear feedback.** Every observation has `<returncode>`; output over
  10k characters is cut to head and tail with a hint to narrow the command.
  Malformed replies get a corrective message instead of ending the run.
- **The prompt carries the workflow**, not the code (see
  [system prompt](../concepts/system-prompt.md)).
- Because it adds so little, the SWE-bench "bash only" leaderboard uses it
  to compare models.

## What Tag can borrow

Compared against `Agent.swift`, `ShellTools.swift` and `ProcessRunner.swift`
on 2026-10-18. Ordered roughly by value.

**Reliability gaps**

1. No system prompt. See [system prompt](../concepts/system-prompt.md).
2. `bash` has no timeout; kill the process group, return partial output.
   A per-call `timeout` argument would improve on mini (60 s is too short
   for `swift build`).
3. Output: 1 MB is an error with no output, and `read_file` has no limit.
   Use head + tail truncation with an elided count and a hint, for every
   tool; better than mini: save the full output to a temp file (pi does).
4. Always report the exit code in one consistent shape; say so when a
   command printed nothing.
5. Tool environment: `PAGER=cat`, `GIT_PAGER=cat`, `MANPAGER=cat`,
   `NO_COLOR=1`, `TERM=dumb`, `TQDM_DISABLE=1`, `PIP_PROGRESS_BAR=off`.
6. API errors end the session. Retry with exponential backoff; abort on
   auth, not-found and context-window errors.
7. An empty reply throws. Feed a corrective message back instead, with a
   separate hint for `finish_reason == "length"`; stop after 3 in a row.
8. No step, cost or wall-time limit per turn.

**Structure**

9. Save the conversation as JSON after every step (debugging, replay,
   evals, fine-tuning).
10. An `Environment` protocol (`execute(command) → output, status`) in
    place of `ProcessRunner`, so a sandbox is one new type.
11. Prompt caching. See [prompt caching](../concepts/prompt-caching.md).
12. Ask for parallel tool calls; run read-only calls concurrently.

**Interaction**

13. Confirmation modes (confirm / yolo / human) with a whitelist of
    commands that never need confirmation.
14. Ctrl-C interrupts the step and asks for a comment, which becomes a user
    message.
15. Human mode: the user runs a shell command and its output joins the
    history.
16. Confirm before finishing; the user can give a new task.

**Measuring**

17. A headless mode (`tag -p "<task>"`, a completion sentinel) so Tag can
    run SWE-bench-style tasks.
18. Compare the five tools against bash only on the same model.

## Notes

- mini's prompt is written for unattended benchmark runs ("MUST include at
  least one tool call", a submit command). In Tag a reply without tool
  calls ends the turn, so those parts don't transfer.
