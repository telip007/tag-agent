---
title: Evaluation loop
summary: A plan for measuring system prompt changes across frontier, cheap and open-weight models, so the prompt works as well on non-frontier models as on frontier ones. Not built yet.
updated: 2026-10-18
---

# Evaluation loop

Status: **a plan, not built.** Nothing here is a decision yet; it is meant
to be worked through and then recorded in `decisions/`.

## Why

[Decision 0009](../decisions/0009-system-prompt.md) keeps the
[system prompt](system-prompt.md) short and adds rules "when a model gets
something wrong". Without measurements, "gets something wrong" means
anecdotes from single sessions. Tag will mostly run on open-weight and
cheaper models (the default is DeepSeek V4.1 Flash), so the prompt has to
work there, not only on frontier models. A short prompt like pi's is tuned
for strong models (see [pi](../sources/pi-coding-agent.md)); whether it is
enough for weaker ones is an open question that only measurement answers.

The goal: every prompt change is run against the same tasks on a fixed set
of models, and accepted only when no model tier gets worse.

## What "performs equally" can mean

A small open model will not match a frontier model's absolute pass rate on
hard tasks; that is a model limit, not a prompt problem. A testable target
is:

1. **No regression on any tier.** A change that helps frontier models but
   costs a cheap model points is rejected (or the cheap tier gets its own
   fix first).
2. **Equal behaviour on the basics.** On easy tasks every tier should get
   the same things right: read before editing, run the tests, ask when the
   request is ambiguous, leave unrelated code alone, end with a short
   summary. These are prompt-controlled, so a gap there is a prompt problem.
3. **Close the gap where the prompt can.** Track the gap between tiers per
   task category; a prompt change that narrows it without hurting the top
   tier is the kind we want.

## Model matrix

Three tiers, two or three models each, pinned by exact OpenRouter model id
in the eval config (ids change; pick them from the catalogue when building):

| Tier | Examples | Why |
| --- | --- | --- |
| Frontier | a current Claude, GPT and Gemini model | the ceiling; checks a change doesn't hurt strong models |
| Cheap / default | DeepSeek V4.1 Flash (Tag's default), similar fast models | what most sessions will use |
| Open-weight, smaller | Qwen, Llama, gpt-oss, Mistral class models | the floor Tag should still handle |

Gotchas for open models on OpenRouter:

- **Provider variance.** The same open model is served by several providers,
  some quantised (e.g. fp8), with different tool-calling support. For evals,
  pin the provider per model so runs are comparable. This conflicts with the
  rule "never set `provider.order`" in [prompt caching](prompt-caching.md);
  that rule is for sessions, the eval harness is the exception.
- **Tool-call reliability** differs more than reasoning: malformed JSON
  arguments, made-up tool names, text instead of a tool call. Measure it on
  its own (see metrics).
- **Context length and degradation:** smaller models lose instructions
  sooner as the conversation grows, so include some long tasks.

## What Tag needs first

From [mini-swe-agent](../sources/mini-swe-agent.md#what-tag-can-borrow):

1. **Headless mode:** `tag -p "<task>"` runs one task to the end without the
   UI and exits (borrow 17).
2. **Saved trajectories:** the full conversation as JSON after every step,
   with usage and cost (borrow 9). Grading reads these.
3. **Model and provider by flag**, so the harness can loop over the matrix.
4. **Limits per run:** steps, cost and wall time (borrow 8), so a looping
   cheap model can't burn the budget.
5. **A sandbox per run:** a fresh copy of the task's fixture repository in a
   temporary folder. Later an `Environment` protocol (borrow 10) for
   containers.
6. **Scripted user replies:** when the agent asks a question, the harness
   answers from the task file (or records that it asked, for the "should
   ask" tasks).

## Task set

Start small and our own; add public benchmarks for calibration later.

**Layer 1: own fixture tasks (20–40).** Small repositories under
`Evals/fixtures/` (Swift, Python, shell) with hidden tests. Categories:

- bug fix with a failing test
- small feature
- refactor that must keep tests green
- question only ("where is X handled?"): no edits expected
- ambiguous request: the right move is to ask
- destructive request (delete files, push): the right move is to ask
- environment traps: `sed -i` on macOS, `cd` not carrying over between bash
  calls, an interactive command that needs a non-interactive flag
- long task: many files, many steps (context degradation)

**Layer 2: behaviour checks** graded from the trajectory, mostly by script:

- read the file before editing it
- ran the build or tests after changing code
- asked on ambiguous or destructive tasks, didn't ask on clear ones
- diff touches only files the task needs (scope)
- final message is 2–4 sentences and names files
- tool-call errors: invalid JSON, unknown tool, failed edits

**Layer 3 (later): public benchmarks.** A small fixed subset of SWE-bench
Verified, run the way mini-swe-agent does, to compare against published
numbers. Caveat: public tasks may be in the models' training data.

## Grading

- **Primary:** hidden tests pass (layer 1) or the scripted check holds
  (layer 2). Deterministic and cheap.
- **LLM judge only where a script can't decide,** e.g. whether a summary is
  accurate. One fixed frontier judge, a short rubric, and spot checks by a
  human.

## Running and reading results

- **Repeats:** at least 3 runs per task and model; cheap models are noisy.
  Report the mean pass rate and the spread, per tier and per category.
- **Metrics per run:** pass/fail, steps, tokens, cost (from OpenRouter
  usage), wall time, tool-call error rate, behaviour checks.
- **Cost estimate** before each run: tasks × models × repeats × average cost
  per run. A guess, not measured: layer 1 on cheap models should cost cents
  per full pass; frontier models dominate the bill.
- **Results** saved as JSON lines per run (prompt version, model, provider,
  task, metrics), committed so changes can be compared over time. No
  personal data or local paths in them; the repository is public.

## The loop

1. Run the baseline: current prompt, full matrix.
2. Pick the worst gap (a tier, a category or a behaviour check).
3. Make **one** prompt change aimed at it, with the reason written down.
4. Re-run the full matrix.
5. Accept if the target improves beyond the noise and no tier drops beyond
   it; otherwise revert.
6. Record the change and the numbers in [log.md](../log.md), and in a
   decision record when it changes a rule.

Ideas the loop would test first, all guesses until measured:

- mini's explicit workflow (explore, reproduce, fix, re-run, edge cases)
  against our short rules, on the cheap tier
- one short example of a good tool call or final summary, for small models
- the reproduce-with-a-test-first rule left out from the
  [Karpathy guidelines](../sources/karpathy-guidelines.md)
- the five tools against bash only (mini borrow 18)

## Open questions

1. **One prompt or variants per tier?** A single prompt is simpler and keeps
   the cache prefix shared; variants only if the eval shows a gap one prompt
   can't close. (Leaning: one prompt.)
2. **Which exact models and providers** make up the matrix, and the budget
   per full run?
3. **Where the harness lives:** a Swift target in this package, or a script
   driving `tag -p`?
4. **How many fixture tasks** before the first baseline, and who writes the
   hidden tests (human-reviewed, so they are trusted)?
5. **Temperature and seeds:** fix them for evals, or run at the defaults
   users get and rely on repeats?
6. **CI:** run a small smoke subset on every prompt change, the full matrix
   on demand?
