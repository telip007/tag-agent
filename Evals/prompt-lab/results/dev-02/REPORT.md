# Development screen 02 — 2026-10-20

Completed: 144/144 native-tool responses, zero infrastructure errors, six frozen
policies × 12 development tasks × two model aliases × one response per cell.
Temperature 0; completion cap 2,048; reasoning uses provider defaults.
Provider: OpenCode Go. No model-generated commands or edits executed.

The metric below is **preferred next action under a surface rubric**. It does
not measure completed code, final authorization handling, test outcomes or
whole-task token efficiency. Do not adopt a prompt from this table.

| Policy | DeepSeek V4.1 Flash score | GLM 5.3 Flash score | Total reported tokens across both models |
| --- | --- | --- | ---: |
| baseline | 8/12 | 9/12 | 31,256 |
| compact | 7/12 | 10/12 | 29,216 |
| workflow | 7/12 | 8/12 | 30,668 |
| evidence | 9/12 | 9/12 | 31,361 |
| examples | 8/12 | 10/12 | 33,408 |
| combined | 8/12 | 9/12 | 41,437 |

197,346 total provider-reported tokens, including cached inputs and reasoning
where counted by the provider. Cash cost and Go allowance debit were not
returned and are unknown. This is usage, not a billing receipt.

## What the run establishes

- Real model requests, native function-call parsing, token capture and frozen
  experiment/result validation work for both selected aliases.
- The combined policy used 41,437 tokens against baseline's 31,256 (32.6% more),
  with the same observed rubric scores on each model. This is a narrow screen
  observation; it does not prove verbose prompts are generally worse.
- Compact rules used 29,216 tokens (6.5% less than baseline), with one fewer
  preferred action on DeepSeek and one more on GLM. A shorter prompt therefore
  did not dominate the baseline across both model samples.
- Evidence rules scored one more preferred action on DeepSeek and tied GLM,
  using 31,361 tokens. One task difference is insufficient to infer superiority.

## Raw-response audit and measurement limits

All failing responses were inspected. The ambiguous-rounding snapshot causes
all policies to inspect the project before asking. Stop/summary snapshots omit
prior edit details and diffs; models often inspect Git to ground their summary.
These responses can be reasonable evidence gathering despite failing a rubric
that expects an immediate question or final answer. Several first-step scores
also penalize compatible multi-tool inspection or harmless shell alternatives.
The current grader is deliberately limited; some companion inspection calls
are accepted by name without complete argument validation. Argument-pattern
matches also do not establish the semantics or safety of shell commands.

Consequently, these counts are calibration data. They are not a ranking of
coding competence or a trustworthy optimization target on their own. Preserve
this run unchanged. Improve task completeness and evaluate whole trajectories
with external functional tests before revising policies based on these failures.
An authorized-action preflight passing this screen does not establish that the
agent subsequently executes the action or avoids redundant confirmation.

`analysis.json` includes task-cluster bootstrap differences against baseline.
These small-sample exploratory intervals do not account for model sampling
noise, candidate selection or multiple comparisons. Zero-width intervals for
identical paired outcomes do not establish equivalence. There was one response
per model/task/policy and no held-out evaluation. The reserved holdout requests
have not run. Model aliases and unpinned upstream routing further limit claims.

## Reproduction and retained evidence

- `frozen.json`: exact prompts, tool schemas, tasks/rubrics, model settings,
  schedule seed, source revision and SHA-256 fingerprints.
- `results.jsonl`: all raw model messages, usage, grades and timings.
- `summary.json`: original runner aggregation.
- `analysis.json`: job-identity audit and exploratory paired analysis.
- `benchmark.py` and `fixtures.py`: exact source snapshots used for this run,
  verified against the manifest hashes. To reproduce the original runner, place
  these at the documented project-relative paths in a separate checkout.

From the repository root:

```sh
python3 Evals/prompt-lab/report.py Evals/prompt-lab/results/dev-02
python3 -m unittest discover -s Evals/prompt-lab -v
```

A new live run requires a fresh output path when source/settings differ.
The diagnostic `dev-01` run remains separate and incomplete; its missing replay
fields and stricter grading make its figures incomparable. No data were silently
replaced or regraded. The production system prompt is unchanged.

Research and remaining full-trajectory requirements:
[experiment design](../../../../wiki/designs/prompt-optimization.md).
