# Three-task multi-file transfer

Complete: **54/54 unique trajectories**, three model aliases × two fixed prompts
× three reserved tasks × three samples. The continued supervisor exited zero
and PID was verified absent before the context stress run began. The original
17 completed rows survived byte-for-byte; only the 37 unrun cells were continued
after the first process explicitly stopped on malformed tool-call history.

Run fingerprint: `98999516c440ab9a2fe4803376083b58b1b7fc7c978487a115bd0be8a96f766d`.
The recommendation freeze, policies, 74 current and archived runtime sources
and compiled bundle remain unchanged. All 51 captured system texts match the
exact templates; three deadline jobs have no captured prompt/outcome. See
`template-verification.json` and `continuations.json`.

| Model | Baseline operational success | Compact operational success | Baseline code passes | Compact code passes |
| --- | ---: | ---: | ---: | ---: |
| DeepSeek | 6/9 | 6/9 | 6/9 | 6/9 |
| GLM | 4/9 | 3/9 | 4/9 | 4/9 |
| Gemini | 5/9 | 4/9 | 6/9 | 4/9 |
| Total | 15/27 | 13/27 | 16/27 | 14/27 |

All 26 original failures have hash-bound entries in `failure-audit.json`:

- Seven normal completions fail conventional quoted-comma CSV parsing.
- Twelve runs reach the common 4,096-token output cap.
- Two GLM compact runs reach the 12-call limit; one leaves externally correct code.
- One GLM compact reply has invalid JSON tool arguments, followed by an HTTP400
  rejection when those arguments are replayed in the next request. The recorded
  output is at the cap, but the precise truncation mechanism is not independently
  proven without a captured finish reason.
- One Gemini baseline request times out before a saved repair; its fifth attempted
  request has no returned usage.
- Three Gemini jobs hit the 180-second supervisor deadline; one baseline tree
  report leaves correct saved code. Their missing outcomes and usage remain unknown.

Every inventory-import cell fails its original oracle. Independent read-only
review reproduced quoted-field failures in both prompt arms and a passing frozen
reference. Conventional quoting is supported by [RFC4180 §2](https://www.rfc-editor.org/rfc/rfc4180#section-2)
and [Python CSV documentation](https://docs.python.org/3/library/csv.html); the RFC
is Informational and dialect differences remain a task-description limitation.
The oracle stops at its first failed assertion, so later transaction and CLI
behavior is unobserved for those failing states. See `csv-format-review.json`.
No grades, tasks, prompts or failed cells were rewritten or replaced.

Recorded usage totals **1,720,389 tokens and 371 attempted model calls**. These
are lower bounds because deadline outcomes and some failed-request usage are
missing. Missing Gemini cache data prevent complete tariff estimates; cash
charges and actual allowance debits are unknown. Correct code does not override
a failed agent completion. Latency is observational under shared provider
infrastructure; all inference budgets stayed fixed.

The ordinary six-task confirmation and this transfer set are kept separate in
`../native-heldout-comparison-01/analysis.json`, followed by a combined nine-task
primary view. The context stress check is a separate experiment, still pending
at this report's completion. This synthetic suite alone does not establish
real-world performance, a universal best prompt or production adoption.
