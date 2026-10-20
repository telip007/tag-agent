# Six-task reserved confirmation

Complete: **108/108 trajectories**, three model aliases × two fixed prompts ×
six reserved tasks × three samples. The supervisor exited zero and its process
was verified terminal before transfer started. This is the first reserved
suite, not the completed nine-task/context validation pipeline.

The compact/standard candidate and baseline were fixed before any reserved
request. Recommendation freeze:
`f17741ca5404e3dfeaa3bc228cec6f998ab834fb24902aec2cc1fd13e18738cf`.
Run fingerprint:
`a75fe42de7cef5ff4d50f54369377ba24a88966a7d334fb580ea1b6e488e8624`.

| Model | Baseline operational success | Compact operational success | Baseline saved code passes | Compact saved code passes |
| --- | ---: | ---: | ---: | ---: |
| DeepSeek | 16/18 | 18/18 | 17/18 | 18/18 |
| GLM | 16/18 | 15/18 | 16/18 | 15/18 |
| Gemini | 17/18 | 18/18 | 18/18 | 18/18 |
| Total | 49/54 | 51/54 | 51/54 | 51/54 |

All original grades remain primary. Eight failed trajectories have hash-bound
audits in `failure-audit.json`:

- Four GLM bool-validation cases, two under each prompt, accept `limit=True`.
  The task's positive-integer wording does not explicitly resolve Python bool;
  this interpretation caveat is recorded in `data-quality.json`.
- One GLM compact case has an unambiguous interval-boundary bug. Its saved
  `Limiter(10, 1)` accepts time 0, then rejects time 10; the explicitly open
  lower interval boundary requires acceptance. The error was reproduced.
- One DeepSeek baseline request timed out before any saved repair.
- One Gemini baseline request timed out after code that passed external tests.
- One DeepSeek baseline job reached the shared 180-second supervisor deadline
  after passing saved code. No outcome/usage was captured for that job; its
  provider/tool cause is unknown.

Compact's higher pooled operational count coexists with a worse GLM result
and a genuine semantic error. The other differences involve transport/deadline
events; they do not establish a causal prompt improvement. Both prompts have
51/54 externally passing saved states. The additional uniform keyed-window
task exclusion removes the genuine boundary error as well as bool cases. It
is a secondary robustness view, not corrected primary quality or an adoption
criterion.

Conditional successful-pair, task-balanced token ratio is **1.062** for compact
versus baseline, exploratory 95% interval **0.968–1.191**. Call ratio is
**1.051**, interval **1.017–1.077**. Resource summaries share five tasks across
all models because no GLM compact keyed-window run succeeded; primary quality
retains all six. The pooled quality difference is +3.70 percentage points,
interval −3.70–9.26. These unadjusted task-cluster intervals do not prove
equivalence, general improvement or a universal best prompt.

Gemini cache data are incomplete, so there is no three-model tariff ratio.
All-attempt token cost per success is unknown for the DeepSeek and Gemini
baseline cells. GLM has complete token usage: baseline 22,375.9 versus compact
25,635.6 tokens per actual success, including failed attempts. Across the run,
2,201,554 tokens and 692 attempted calls were recorded; both are lower bounds
because the deadline job has no outcome and failed requests have unknown
usage. Cash charges and actual allowance debits remain unknown.

All 74 runtime source files and their archives match the frozen hashes; the
compiled bundle matches the recommendation freeze. All 107 captured redacted
system texts match the exact baseline/recommendation templates. The deadline
job's system text is unavailable and is not inferred. See
`template-verification.json`, `analysis.json` and the raw rows/details.

The predeclared 54-cell multi-file transfer and 18-condition context stress
checks remain separate. The prompt is not tuned on these results, and no final
choice or production activation follows from this first confirmation suite.
