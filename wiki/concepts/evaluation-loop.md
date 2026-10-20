---
title: Evaluation loop
summary: Native prompt evaluation and completed reserved comparisons; retain baseline because compact did not confirm a replacement advantage.
updated: 2026-10-20
---

# Evaluation loop

Status: **planned prompt measurements complete; retain baseline/standard.**
The [final recommendation](../../Evals/prompt-lab/recommendation/FINAL.md)
provides exact text, hashes, comparisons, limitations and reproduction commands.
Eight cores and a lean-scaffold ablation were explored; the strict repeated
selection matrix has 528 cells. The frozen compact development winner and
baseline then received 162 ordinary reserved trajectories and 18 separate
context conditions. Ordinary operational success tied at 64/81, saved code
passed in 67/81 baseline versus 65/81 compact, and no token saving was confirmed.
The context check shows a tradeoff on one task, not independent new tasks.
Local verification passed with 318 Swift tests, 91.5% coverage and 42 offline
reporting tests; a closing read-only review found no Important or Critical issue.

The research supervisor uses the actual Tag loop, adapters and tools in synthetic
fixture directories, with external functional grading and bounded calls/tokens/
time. The [decision screen](../../Evals/prompt-lab/README.md) did not execute
returned actions and did not select a coding winner. Current model coverage is
three Go aliases across two native wire formats; broad frontier/small-model
coverage, a production headless CLI and public SWE-bench calibration below
remain roadmap proposals. Production `SystemPrompt.swift` is unchanged.

The following sections retain that broader production-facing proposal and
research questions; they are not claims that every proposed capability exists.
Commands, frozen evidence and current behavior are in the
[research README](../../Evals/prompt-lab/README.md).

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
   summary. Prompt changes can affect these behaviors; a gap still requires investigation
   of the model, tools, harness and grading before assigning a cause.
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

The list below is the original production-facing proposal. The research bridge
provides fixture execution and trajectory recording through tests; the user CLI
still does not expose these evaluation flags.

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
- **Results:** frozen manifests, source archives, hashes, audits and derived
  reports support comparisons. Current immutable raw JSONL/details stay local
  and are excluded from Git because native logs can retain toolchain metadata.
  Any future public raw projection needs separate redaction and provenance.

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


The prompt lab now also varies the system scaffold with `--scaffold lean`: a
short identity and no prose tool list. It preserves actual API tools, tool
guidelines, environment and project instructions; the standard control retains
the exact native renderer. Sample labels gain `_lean`, and the frozen manifest
records the scaffold separately. See the prompt optimization design for the
completed eight-policy exploration, fixture ambiguity audit, repeated selection
and reserved validation. The [final choice](../../Evals/prompt-lab/recommendation/FINAL.md)
retains the existing baseline; shorter text alone did not establish efficiency.

## Gotchas

Recorded token totals are lower bounds when a request fails without usage.
Do not divide such a total by successful turns and present it as complete
cost per success. Both native and family reports now leave that metric unknown
unless every attempted inference has usage; known consumption from failed
turns still counts. A missing-request regression covers this distinction.
See `Evals/prompt-lab/reporting-review.json` and the research design.
