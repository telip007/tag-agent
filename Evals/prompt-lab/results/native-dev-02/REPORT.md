# Native development comparison 02

Completed all 72 scheduled trajectories: 12 tasks × three policies × two model
aliases × one sample per cell. The tasks comprise ten coding fixtures and two
behavioral fixtures. The actual Tag Agent loop, adapters and tools executed.

**70/72 end-to-end successes after one explicitly recorded behavioral-rubric
correction.** Two trajectories ended with provider transport timeouts. One had
already produced code that passed external tests; the other implementation was
unfinished. All 58 normally completed coding trajectories passed their external
checks. Across all 60 coding attempts, 59 saved code states passed. Both
behavioral task types were fulfilled in all 12 attempts after review.

The raw grades remain unchanged. One valid `Please choose` clarification was
rejected by the original punctuation rule. `adjudications.json` records its
review, rationale and the exact trajectory hash; `analysis.json` displays raw
and reviewed scores separately. The same criterion was audited across all
completed behavioral tasks. No code-test failure was overridden.

| Model | Policy | Reviewed success | Calls attempted | Reported tokens |
| --- | --- | ---: | ---: | ---: |
| deepseek-v4.1-flash | baseline | 11/12 | 64 | 150,662 |
| deepseek-v4.1-flash | compact | 12/12 | 70 | 167,364 |
| deepseek-v4.1-flash | evidence | 12/12 | 66 | 163,418 |
| glm-5.3-flash | baseline | 12/12 | 87 | 200,921 |
| glm-5.3-flash | compact | 12/12 | 70 | 149,248 |
| glm-5.3-flash | evidence | 11/12 | 63 | 132,012 |

420 inference calls were attempted and 963,625 tokens were reported. Usage for
failed requests without completed replies is unknown; this total is a lower
bound, not a billing receipt. Complete source snapshots and the compiled-bundle
fingerprint pin the native harness used for this run.

## Preliminary resource findings

On GLM, compact reduced total reported tokens by 25.7% against baseline, but its
recorded-usage allowance-rate estimate was 2.7% higher. The cached-input mix was
different. This is observed under the provider's cache state; cache warming and
upstream routing were not controlled, so it does not prove a causal threshold
or universal advantage for longer prompts. Actual cash charges and allowance
debits were not returned.

DeepSeek and GLM showed different tradeoffs. A prompt-length ranking cannot
select one shared winner. The comparison has one sample per task/policy/model;
provider aliases can change and transport variance is visible. Its estimates
and bootstrap intervals are exploratory. Repetitions and held-out functional
confirmation remain required before recommendation.

`analysis.json` reports cached input, uncached input and output separately and
uses the dated, sourced Go rate card for recorded-usage estimates. DeepSeek's
peak/off-peak timing is left unresolved as a range. Groups with incomplete
response usage cannot establish their full run cost.

## Evidence and next experiment

- `frozen.json`: tasks, exact policy text, controls, schedule and source hashes.
- `results.jsonl`: original outcomes, responses, tool events and grading.
- `runs/`: final files, external checks and native process logs.
- `source/`: the 69 source files verified against the manifest.
- `adjudications.json`: explicit behavioral review, preserving original grades.
- `analysis.json`: completeness, source integrity and separated outcome/resource metrics.

The `adaptive_compact` proposal was written before final selection and before
opening any reserved confirmation result. It combines concise instructions with
trust and evidence-based stopping. It will first run on development tasks.
The [selection protocol](../../selection-protocol.md) governs repeats and frozen
finalist confirmation. No production system prompt has been replaced.

Recompute from the repository root:

```sh
python3 Evals/prompt-lab/native_report.py Evals/prompt-lab/results/native-dev-02
```
