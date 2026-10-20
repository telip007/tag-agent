---
title: Prompt optimization experiments
summary: Research and a staged experiment to find a strong, efficient Tag prompt using measured behavior and held-out coding tasks.
updated: 2026-10-20
---

# Prompt optimization experiments

The requested outcome is a powerful, efficient system prompt, supported by
benchmarks and academic research. A universal optimum is not a measurable
claim. The operational target is a Pareto frontier: task success and reliable
behavior against total tokens, model calls, latency and reported cost, on a
declared model/task distribution. A short prompt can cause expensive retries;
prompt length alone is not efficiency.

## Research and hypotheses

These are hypotheses to test in Tag, not transferred performance claims:

| Primary source | Finding relevant to this experiment | Test |
| --- | --- | --- |
| [The Prompt Report, §2](https://arxiv.org/html/2406.06608v1) | Separates examples, decomposition, ensembling and self-criticism into distinct techniques. | Compare compact rules, a workflow and examples; avoid combining every technique by default. |
| [MIPRO, §3–6 and Appendix B.1](https://arxiv.org/html/2406.11695v1) | Searches instructions and demonstrations with downstream measurements and separate data splits. | Freeze candidates and development/holdout splits before measuring; optimize development only. |
| [GEPA, §3 and Algorithm 1–2](https://arxiv.org/pdf/2507.19457v2) | Uses trajectory feedback to propose prompt revisions and retain complementary candidates, separating feedback and candidate-selection data. | Use audited trajectory feedback for manual proposals and compare quality/resource tradeoffs. GEPA's instance-wise Pareto selection and reflective optimizer are not implemented. |
| [Self-Refine, §2–3](https://arxiv.org/html/2303.17651v2) | Iterated actionable feedback improves some tasks in the studied models. | Test explicit verification; account for all added calls. A single instruction to reflect is not the Self-Refine algorithm. |
| [Cannot Self-Correct, §3–5](https://arxiv.org/html/2310.01798v2) | Intrinsic reasoning correction can fail without external feedback in the studied settings. | Prefer actual tool/test observations over repeated unsupported self-assessment. This is not proof that all modern self-correction fails. |
| [Lost in the Middle, §2–3](https://arxiv.org/html/2307.03172v1) | Retrieval quality depends on evidence position in the evaluated contexts. | Include distracting context; later vary relevant evidence position and conversation length. |
| [OpenAI prompt engineering](https://developers.openai.com/api/docs/guides/prompt-engineering) | Recommends representative fixtures and evaluation before production prompt changes. | Keep the production prompt unchanged until end-to-end evidence supports a replacement. |

## Experiment stages

1. **Decision screen.** Real native tool calls on fixed conversation snapshots,
   using the five Tag tool schemas. Deterministic task-specific graders measure
   the next action. No generated command or edit executes. This isolates prompt
   behavior cheaply but does not measure completed coding tasks.
2. **Full trajectories.** Run finalists in fresh fixture repositories with Tag's
   actual tool implementations; grade resulting code with external tests,
   compare baseline and candidates over at least three repeats per model/task.
   Include Python, shell and Swift; bug fixes, features, read-only questions,
   ambiguous requirements and longer tasks. Pin model IDs and capture provider
   metadata when available. Provider aliases are not immutable weight versions.
3. **Optimize and ablate.** Use development failures to propose small rule
   changes. Test adaptive effort, evidence gates and examples separately. Freeze
   finalist text before opening holdout results. After any holdout-driven
   revision, that split becomes development and a fresh holdout is required.
4. **Confirm.** Evaluate frozen finalists on unseen tasks and multiple model
   tiers. Report paired task-level uncertainty, regressions by category/model,
   token/call/latency distributions, unknown cost fields and all infrastructure
   failures. Repeated samples of one task are not independent tasks.

## Initial implementation choices

The first runner is a standard-library Python research utility in
`Evals/prompt-lab/`, separate from Tag's interactive loop. It reads the existing
OpenCode Go key without printing or copying it into results, identifies itself
with its own user agent and gives each conversation a stable session header,
as required by [Go documentation](https://opencode.ai/v2/docs/console/go).
Only synthetic fixtures and public prompt text are sent. There is no model
judge and no added subscription or billing configuration.

Initial candidates: current Tag rules, compact rules, explicit workflow,
evidence-gated adaptive effort, that policy plus short examples, and a verbose
combined policy. The novel combination is a hypothesis, not a novelty claim
against the literature. All candidates receive the same tool definitions and
environment. The current baseline's source revision and prompt hashes must be
recorded. Changes outside the research files are not required for the screen.

## Completion requirements

- A usable prompt artifact with its exact text and hash.
- Opened primary research, mapped to the strategies actually tested.
- Reproducible runner, task definitions, raw outputs and graded results.
- Baseline comparisons on full coding runs, held-out tasks and model tiers.
- Clear quality/efficiency tradeoffs and uncertainty; no universal-best claim.
- Project checks pass before calling the repository work done.

Current status (2026-10-20): all planned measurements are complete: 632 new
development trajectories (including the reused 528-cell selection matrix),
162 ordinary reserved trajectories and 18 separate context conditions.
The final practical recommendation is baseline/standard; compact's frozen
development success did not confirm a replacement advantage. Ordinary
operational scores tie at 64/81, code passes are 67/81 baseline versus 65/81
compact, and the conditional token ratio is 0.999327 with uncertain limits.
Context operational totals are 7/9 baseline versus 6/9 compact, while code
passes are 7/9 versus 8/9: neither uniformly dominates.

The [final report and exact prompt](../../Evals/prompt-lab/recommendation/FINAL.md)
is authoritative for the current recommendation. Local verification passed:
318 Swift tests, 91.5% coverage, 42 offline tests and exact report reproduction;
closing read-only review found no Important or Critical issue. The sections below retain the successive
stages and their historical open states; the
[selection protocol](../../Evals/prompt-lab/selection-protocol.md) was frozen
before reserved requests and was not tuned on their results. The original
[144-request screen](../../Evals/prompt-lab/results/dev-02/REPORT.md) is calibration
evidence. No production prompt replacement has been installed.

## Evaluator lessons

The connectivity check exposed a false negative: searching for a relevant
declaration can be a reasonable first step before reading a supplied file path.
The interrupted `dev-01` also showed that several independent inspection calls
can be valid, and an authorized push can reasonably begin with Git preflight.
These alternatives were accepted before a fresh `dev-02` screen. The score is
still a preferred-next-action metric, not a complete semantic correctness grade.

DeepSeek returned HTTP 400 for synthetic previous assistant calls lacking
`reasoning_content`; its error explicitly required replay of this field in
thinking mode. A diagnostic with an empty field was accepted. Synthetic history
now includes an empty field, without fabricated reasoning. Failed/partial runs
remain saved separately; no infrastructure error is counted as a valid
behavioral observation. The current utility stops on HTTP 4xx after the active
batch. These observations concern the Python screen, not a defect established
in Tag's Swift adapters.

## First complete screen

`dev-02` contains six policies, 12 development snapshots and two discovered
OpenCode Go model aliases, with one response per combination. Total reported
usage: 197,346 tokens; cash cost and allowance debit are unknown. All prompts,
tasks, schemas, settings, source hashes, messages and derived grades are retained.

The compact policy used 6.5% fewer total tokens than baseline but scored one
fewer preferred action on DeepSeek and one more on GLM. The combined verbose
policy used 32.6% more tokens with identical scores to baseline on both models.
These are observations in a small surface screen, not findings about general
coding quality. The raw-response audit identified sparse histories and reasonable
inspection alternatives that the graders penalize. No candidate should be
selected by optimizing these counts. The held-out requests have not run.

The screen motivated full coding trajectories with actual tools, complete
initial states and external functional checks. It remains calibration evidence;
subsequent stages below use development-only feedback and separate confirmation.
A production adoption decision still needs repeated, held-out and model-family
evidence. The [evaluation loop](../concepts/evaluation-loop.md)
still describes those outstanding requirements.

## Full-trajectory implementation

The next experiment uses an opt-in Swift test bridge, with no change to the
production CLI. The bridge runs the actual `Agent`, `OpenCodeGoProvider` and
`ToolDefinition.builtIn` against a fresh fixture directory. A recording model
wrapper replaces only the general rules in the outgoing system message;
baseline keeps the actual rendered prompt unchanged. Tools, project instructions,
environment, user-message dating and the production loop remain shared.

An injected transport applies a common completion cap and temperature for Chat
Completions. A model-call limit and an external process deadline bound each job.
The Python supervisor owns fixtures and external grading; model claims never
determine functional success. Visible checks stay in each fixture and external
checks run against saved files after the agent exits. Every run saves final
files, tool events, responses, usage, termination and grader output.

- [x] Implement and test the Swift recording/limit/prompt bridge; disabled by default.
- [x] Add complete Python, shell and Swift fixtures plus externally checked expected results.
- [x] Verify unmodified fixtures fail the intended checks and reference repairs pass them.
- [x] Run connectivity and full-trajectory development comparisons before expanding repeats/model coverage.
- [x] Freeze finalists, then run confirmation tasks and produce a measured recommendation.

The fixture working directory is separate from the developer checkout. Tag's
existing tools protect its credential directory, but they are not a security
sandbox; do not claim isolation against malicious generated code. This stage
contains ordinary synthetic coding tasks and no real push/publication tasks.

`native-smoke-02` passed the clamp fixture on both baseline models, using five
and six actual model calls (19,146 reported tokens in total). These validate the
native pipeline only. `native-smoke-01` failed during result serialization and
is retained as an infrastructure diagnostic with incomplete usage. Structured
redaction regression tests now preserve JSON structure and later evidence.
The native supervisor uses Swift's compiled test helper, with the required
XCTest runtime paths, to avoid serializing jobs behind SwiftPM's package lock.

## Native development interruption and repair

`native-dev-01` stopped after 20 of 72 scheduled jobs: 18 completed and passed,
one model request timed out and one job reached the process deadline. This
unbalanced matrix cannot rank policies. Source snapshots and failed outcomes
are retained; see its [report](../../Evals/prompt-lab/results/native-dev-01/REPORT.md).

A reconstructed follow-up without `reasoning_content` returned HTTP 400; adding
an empty field returned HTTP 200. Both selected models' catalogue metadata asks
for this interleaved field. Inspection found that the native encoder omitted
empty reasoning even when that field was configured. A regression failed on
the omission; the repaired encoder sends own-format reasoning or an empty value
when configured, and still omits the field when disabled. All eight adapter unit
tests then passed. This proves a compatibility repair, not timeout causation.
Subsequent comparisons need a new harness fingerprint.

[DeepSeek's documentation](https://api-docs.deepseek.com/guides/thinking_mode/)
requires prior assistant reasoning fields for tool-enabled conversations. It
also states that thinking mode ignores temperature. The experiment requests
temperature zero; it does not establish deterministic generation on DeepSeek.

Six additional functional confirmation tasks were authored and their oracles
validated before selecting any finalist: keyed rate limits, dependency ordering,
lazy chunks, atomic JSON writes, arbitrary-length numeric versions and shell text
record counting. Their frozen source and definitions are in
`Evals/prompt-lab/results/confirmation-reserve-01/`; no subject requests have
used them. They supplement the older reserved next-action split and do not
replace the full-trajectory confirmation requirement.


## First complete native development comparison

`native-dev-02` recorded all 72 scheduled trajectories. The reviewed score is
70/72 end-to-end successes; the original score was 69/72 because one correct
`Please choose` clarification lacked a question mark. A separate hashed
adjudication preserves the original grade and documents the uniform behavioral
criterion. Two provider transport timeouts remain failed outcomes. All 58
normally completed coding runs passed external checks; 59/60 saved coding states
passed, including one interrupted run whose final model request failed.

The [full report](../../Evals/prompt-lab/results/native-dev-02/REPORT.md)
separates code checks, behavior, operational failure and usage. On GLM, compact
used 25.7% fewer total reported tokens than baseline but had a 2.7% higher
recorded-usage allowance-rate estimate under the observed cache state. That
single run does not establish a causal cache threshold or universal cost result.
The sourced rate card records a DeepSeek peak/off-peak range and does not imply
an actual cash charge or allowance debit.

A 98-word hybrid proposal combines compact wording with explicit trust and
evidence-based stopping. Its exact proposal and hash are stored in
`Evals/prompt-lab/proposals/adaptive-compact.json`. Its completed development evaluation is recorded below. The [selection protocol](../../Evals/prompt-lab/selection-protocol.md)
was written before any reserved functional confirmation request.

The research controller can load explicit policy files, keep follow-up repeat
IDs distinct, and validate confirmation task definitions against the reserved
manifest. Baseline cannot be overridden by a custom policy. Research transport
support extends the same output cap to Gemini while preserving its thinking
configuration and content; an actual Gemini smoke is required before wider use.


Gemini's native baseline smoke passed the clamp task with six model calls and
10,660 reported tokens. Its research transport cap uses `maxOutputTokens`
inside `generationConfig`; tests preserve thinking configuration and content.
The complete repository check passed at 91.5% coverage, and 23 Python tests
passed after adding resource/adjudication integrity checks.

The hybrid development run initially recorded four cells: three successes and
one GLM reasoning-only reply at the 4,096-token cap before editing. That remains
a valid subject budget failure. After confirming the process terminal, the same
frozen configuration resumes only the twenty unrun cells. The failed cell is
not retried or adjudicated as success. Finalists remain unselected.


The hybrid run subsequently completed all 24 cells: DeepSeek 12/12, GLM 10/12.
Its second retained GLM failure was the call limit after a passing Swift patch.
The [hybrid report](../../Evals/prompt-lab/results/native-hybrid-dev-01/REPORT.md)
keeps these subject budget failures distinct from transport errors. The native
exploration family now explicitly contains eight general policies, including a
minimal control; workflow, examples and combined policies also require native
runs because the action screen alone cannot eliminate them. The remaining 96
native exploration cells run under their own frozen manifest.

Before final confirmation, a separate standard/lean scaffold ablation will test
whether removing redundant prose tool summaries and shortening identity improves
the full prompt. Actual API tools, tool-use rules, environment and project
instructions remain intact. Core-policy selection and structural selection must
both precede opening the reserved functional confirmation results.


## Cross-run analysis and fixture audit

The family reporter audits each native run and rejects duplicate sample
identities, incompatible generation controls, changed task definitions and
policy text changes under an existing label. Reports retain all raw outcomes
and show conditional resource ratios separately from end-to-end success.
Different native-bundle hashes are displayed explicitly; the Gemini-only
research transport addition did not change the existing Chat Completions
request construction. These pooled exploratory observations do not replace
a repeated contemporaneous finalist comparison.

A GLM/combined external failure on `config-precedence` was caused by accepting
numeric `2.5` via `int()`. The task explicitly rejects non-integer strings
but leaves numeric-float acceptance unspecified. Its original failed grade
is retained. Before selection or confirmation, the entire task was excluded
uniformly from primary development selection, with all-task sensitivity
retained. No code-test pass is adjudicated and no fixture is rewritten.
Evidence and hashes: `Evals/prompt-lab/results/native-family-comparison-01/data-quality.json`.


## Completed policy-family exploration and structural treatment

All 192 native exploration cells across eight core policies are now recorded.
The last 96-cell run completed with 93 end-to-end successes: one under-specified
config float check, one call-limit failure after passing code, and one
reasoning-only generation-limit failure without a repair. The latter two are
retained subject budget failures. There were no transport errors in that run.
See its [report](../../Evals/prompt-lab/results/native-family-dev-01/REPORT.md).

Primary selection keeps all raw grades and uniformly excludes the config task;
the 176 remaining cells have 170 reviewed successes. The development shortlist
is baseline, compact, evidence and minimal. Workflow/combined offered higher
pooled conditional resource ratios than compact at the same observed primary
success count; adaptive/examples retained budget failures without an observed
Pareto advantage. These are single-sample screening decisions, not proof of
inferiority or a final winner. The exact shortlist and reasons are in
`Evals/prompt-lab/proposals/development-shortlist.json`.

The research wrapper now accepts an explicit standard/lean scaffold. Lean
shortens identity to `You are Tag, a coding agent.` and omits the prose tool
list; selected core rules, tool guidelines, environment and project
instructions remain. Actual API schemas are unchanged, verified through the
real Agent request. Three new scaffold tests were observed failing before
implementation; all nine scaffold/policy/transport tests then passed. Standard
baseline remains the exact renderer. Production prompt source is unchanged.
A live smoke and 88 lean development cells are planned before repeated
finalists and unused functional confirmation.


The full repository check after scaffold implementation passed with 205 TagKit
tests and 113 ModelKit tests (normal live suites disabled), 91.5% source coverage
and the unchanged 80% gate. All 29 Python evaluator/report tests passed. Both
lean native clamp smokes then completed and passed external checks: DeepSeek
seven calls / 13,937 tokens, GLM five calls / 8,301. These diagnose the execution
path and are not reused as development sample zero. The 88-cell structural
comparison has its own frozen manifest and source archive in
`Evals/prompt-lab/results/native-scaffold-dev-01/`.


## Repeat-aware analysis and reserved multi-file transfer

The pooled reporter now includes all-attempt tokens/tariff value per reviewed
success when every attempted inference has complete usage. Failed attempt
usage is included, rather than hidden by successful-pair conditioning. Its
exploratory joint intervals resample common whole tasks, average repeats within
model/task, and weight models equally. Unit tests demonstrate that repeating
the same task does not manufacture independent task clusters, missing usage
does not imply savings, and failed attempt usage contributes to cost per success.

Three multi-file transfer repositories have been authored and frozen before
final selection or any reserved subject request. All original implementations
fail and all reference implementations pass external checks. They cover
transactional inventory import plus CLI, streaming framing plus strict UTF-8
client, and recursive text inventory plus JSON CLI. They add a transfer test
after final prompt freeze, separately from the six original confirmation
tasks; no tuning on either reserved set preserves its held-out status. These
remain authored synthetic repositories, not independent real-world SWE tasks.
Evidence: `Evals/prompt-lab/results/transfer-reserve-01/`.

The scaffold exploration first stopped after 52/88 cells on two requests
reporting `The network connection was lost.`. Both failures and an earlier
call-limit failure are preserved. After terminal process verification, the
identical frozen invocation resumed only the 36 unrun cells. No failed
trajectory was retried and no scaffold result was used as a final selection.


## Complete scaffold ablation and interleaved repetitions

The scaffold run finished all 88 cells: 85 successful agent turns, all 72 saved
coding states externally passing, and all 14 normally completed behavioral
answers satisfying their rubric. Two lost connections on behavioral tasks and
one call-limit failure after passing code remain failures. It attempted 507
model calls and reported 1,151,752 tokens; failed-request usage is incomplete.
See its [report](../../Evals/prompt-lab/results/native-scaffold-dev-01/REPORT.md).

The repeated comparison now interleaves all four shortlisted cores in both
scaffolds under one shuffled schedule with two workers. It adds repeat IDs 1
and 2 (352 fresh cells), retaining sample zero exactly once for a total of
528 selected-template trajectories. This limits chronology differences between
representations; it does not control upstream cache/routing or pin immutable
weights. The predeclared design and compatibility requirements are in
`Evals/prompt-lab/proposals/repeated-comparison.json`.

Both mixed-schedule and fixed-template diagnostic smokes passed. The latter
compares the true standard baseline against a fixed lean alias of the compact
core, validating the future confirmation interface without adding a new core
policy or selection sample. Per-candidate scaffold metadata and worker count
are frozen in new manifests. Reserved-suite task and manifest tampering are
rejected. All 34 Python tests pass; the Swift source/bundle is unchanged since
the previously passing full repository check. Known connection-loss failures
now allow other scheduled cells to continue, without retrying failed cells;
the three-consecutive-error and unexpected/auth failure stops remain.

A supplemental near-start Go/models.dev catalogue snapshot records the three
model descriptors in the repeat directory. It is not a proof of each job's
in-memory catalogue or a backend-weight pin. The actual response metadata does
not establish immutable model weights or backend routing.


## Context-position reserve and first repeated budget failure

A secondary context-position stress check is now predeclared before final
selection, covering the remaining position/length hypothesis in the research
table. It reuses the frozen framed-client transfer task with identical task and
two archive blocks, ordered at beginning/middle/end. The deterministic archive
has 125,952 ASCII characters; actual tokens remain provider-reported. Baseline
and the final frozen recommendation each receive one attempt per condition on
all three models (18 trajectories). These are conditions for one task, not
independent new tasks or a Lost in the Middle reproduction. The nine-task
three-repeat confirmation/transfer comparison remains unchanged. Renderer
tests pass; controller integration waits for the active frozen repeats to end.
See `Evals/prompt-lab/results/context-reserve-01/`. No further experimental
phases are planned beyond the fixed pipeline.

The first retained repeat failure was GLM/minimal_lean/shell-log-count/sample 1.
Four model replies produced six successful inspection calls but no edit. Its
last reply reported exactly 4,096 output tokens, reasoning only, followed by
an empty-reply failure. The unchanged code failed external checks. The hashed
author audit is in `results/native-repeat-dev-01/failure-audit.json`; no retry
or grade override occurred. One observation does not establish prompt causation.


A later repeated GLM/minimal_lean Swift slug run completed normally but failed
external tests: its shared uppercase/digit branch adds 32 to ASCII digits.
Compiling the saved source confirms `slug("ABC123") == "abcQRS"`, against
the explicit required `abc123`. Visible checks were observed but lacked a digit
case. The failed functional grade is retained. A different apparent failure
was a correct unchanged-file rounding-choice request inside bold Markdown; a
separate hashed behavioral adjudication accepts it under the existing explicit
choice criterion, preserving the original raw grade. Both author audits are in
`results/native-repeat-dev-01/failure-audit.json`; no code-test override or
failed-cell retry occurred. All 37 Python checks currently pass.


## Exact tested template catalogue

[The template catalogue](../../Evals/prompt-lab/templates/README.md) contains
all twelve tested core/scaffold combinations with exact text hashes, native
tool guidelines and explicit environment/project parameters. Filling those
parameters reproduced all 280 completed exploration prompts byte-for-byte.
Actual observed repeat prompts are checked separately against the same fixed
catalogue in `results/native-repeat-dev-01/template-verification.json`.
A winning template is not selected by this export. Static text and word counts
are descriptive; comparisons use provider-reported usage and outcomes.

The minimal rule is five whitespace-separated words, correcting an earlier
six-word description in the family report. No experimental text or raw result
changed. Its full system text includes native tool guidance and session/project
fields; actual API tool schemas remain separate and unchanged.

## Read-only harness review

A separate read-only reviewer inspected the native bridge, inference controls,
raw/detail identity, grading, source compatibility, paired statistics and
template provenance. It found no Critical or Important issue and one Minor
reporting inconsistency: the single-run reporter divided recorded tokens by
successes even when failed requests had unknown usage. The family selector
already returned unknown for that case. A new missing-request regression
failed before the fix and passed afterwards; all 38 offline Python tests pass.
The corrected native reporter preserves recorded totals but returns null for
per-success tokens unless all attempted-request usage is complete, including
known usage of failures. Derived completed reports were refreshed; raw results,
grades, manifests and pinned runtime remain unchanged. Details and affected
metrics: `Evals/prompt-lab/reporting-review.json`.

The review supports continuing the pinned experiment. It does not select a
winner, replace reserved confirmation or approve production activation.

## Complete repeated comparison and development choice

All 352 new repeat trajectories are recorded after a verified exit-zero process
end. They contain 345 reviewed successful agent turns (344 raw), 284 externally
passing coding states out of 288, and all 64 behavioral cases passing after one
separate hashed Markdown adjudication. Three generation caps, three call-limit
failures and one genuine normal-completion code error remain failed. All eight
raw failures are audited; all 352 actual system texts match the fixed catalogue.
No failed sample was retried or overwritten.

The strict repeat-selection exporter verifies exactly 528 unique planned cells,
including the declared sample-zero origins and unchanged task/policy hashes.
Compact/standard and evidence/lean each completed 66/66; baseline completed
64/66. Compact has lower complete all-attempt tokens and rate values than
evidence/lean on both models, so it is the practical development choice for
reserved confirmation. The conditional task-balanced token ratio against
baseline is 0.951 (exploratory interval 0.860–1.051); rate-value ratio is 0.992
(0.896–1.087). These do not establish a cost improvement or universal superiority.
Compact/lean's stronger conditional savings retain two GLM failures. See the
[complete comparison](../../Evals/prompt-lab/results/native-repeat-comparison-01/README.md)
and [prepared exact recommendation](../../Evals/prompt-lab/recommendation/REPORT.md).

After the repeat process ended, the controller was connected to the unchanged
reserved context renderer. Its profile verifies the frozen task, renderer,
model and position; the manifest archives context inputs. Differing contexts
cannot be pooled by the family reporter. Without the flag, task text remains
exact. A red-then-green regression also accepts Markdown-wrapped explicit
choices under the existing unchanged-file criterion, without rewriting old
grades. All 40 Python tests pass and a dry run schedules six cases per position
without subject requests. A separate read-only reviewer found no Important or
Critical issue in these integrations or the strict selected matrix. The full
repository check and recommendation freeze precede reserved requests.

The required full repository check then passed: 205 TagKit plus 113 ModelKit
tests, 91.5% of 6,968 lines, unchanged 80% minimum. The exact compact/standard
policy and full system-text template were frozen before any reserved request.
Freeze fingerprint: `f17741ca5404e3dfeaa3bc228cec6f998ab834fb24902aec2cc1fd13e18738cf`;
template SHA-256: `f4e7dc7a9b62728054c19dd2e86d1214a04f56872570f825ff5c8a1c41c63cf2`.
The immutable `recommendation/FREEZE.json` binds development evidence, assets,
reserved suites and controls. It records zero reserved subject trajectories
before freeze. The compiled bundle remains identical to the repeated run.

Post-freeze `native-confirmation-01` is now running 108 cells: baseline versus
recommendation × six reserved tasks × three models × three samples. Its
74 source files are archived and hash-verified. Transfer's 54 cells and the
18 context conditions remain pending, so no final winner or completion is
claimed. No source/controller edits or bundle rebuilds occur during this run.

The first reserved failure exposes an interpretation caveat: GLM/baseline
keyed-window/sample 1 accepts `limit=True`, whereas the oracle rejects it.
The task requires a positive integer without explicitly excluding Python bool;
the separately reserved lazy-chunks task does explicitly exclude bool. A
read-only reviewer judged this materially ambiguous. Keep the original failed
grade in primary all-task confirmation. Show a separate whole-task sensitivity
excluding keyed-window uniformly across policies/models/repeats, explicitly
identified as an audit after the first outcome. Do not delete one assertion,
override a code grade, retry a failure or tune the frozen prompt. The exact
task/detail hashes and decision are in `native-confirmation-01/data-quality.json`
and `failure-audit.json`. This case alone is not a prompt-regression claim.

## Reserved-suite report integrity

`Evals/prompt-lab/confirmation_report.py` audits the six-task confirmation and
three-task transfer suites against the immutable choice. It binds exact models,
policies, controls, compiled bundle, reserved task definitions, required runtime
inputs and archived source hashes. The ordinary suites remain separately
reported, with an additional nine-task summary using unique task/sample IDs.
Primary grades keep every task; the post-freeze keyed-window caveat is shown
only as an additional uniform whole-task sensitivity. Context conditions do not
enter this independent-task summary.

Missing suites, incomplete coverage and unaudited failures prevent readiness for
final interpretation. Report generation fails if live results change during its
read, rather than associating a stale row set with a newer file hash. A regression
first exposed an accepted missing source binding; it now fails validation. Tests
also verify that sensitivity does not mutate or selectively regrade primary
rows. All 42 offline Python tests pass; a separate read-only reviewer found no
Important or Critical helper issue. Native controls and frozen artifacts remain
unchanged during collection. The live report is an explicit partial audit, not
proof of completion or a confirmed winner.

A later GLM/recommendation keyed-window/sample 0 failure is unambiguous and
independent of bool validation: `Limiter(10, 1)` accepts an event at time 0,
then incorrectly rejects time 10 because the repair retains `now - t <= window`.
The explicit interval `(now-window, now]` requires that old event to expire.
Its raw functional failure is retained and the saved-code counterexample was
reproduced. The whole-task sensitivity necessarily removes this genuine error
too; it is a secondary robustness view, not corrected quality or a substitute
for the primary score. `native-confirmation-01/data-quality.json` now records
this limitation and its hash-bound audit. The prompt remains frozen pending
the full validation set; a development score is not final confirmation.

## Completed six-task reserved confirmation

All 108 cells are recorded after a verified exit-zero terminal process.
Baseline completed 49/54 and compact 51/54; both have 51/54 externally passing
saved code states. Per-model operational counts are DeepSeek 16/18 versus 18/18,
GLM 16/18 versus 15/18 and Gemini 17/18 versus 18/18. Four bool-interpretation
failures are evenly split between prompts. Compact also has the genuine GLM
boundary error; baseline has two request timeouts and a supervisor deadline,
two after correct saved code. All eight failures are hash-audited and unchanged.

The conditional task-balanced token ratio is 1.062 (exploratory interval
0.968–1.191), with call ratio 1.051 (1.017–1.077). Resource summaries use five
common tasks; primary quality keeps all six. Gemini cache data prevent a full
three-model tariff ratio. Missing failed-request/deadline usage remains unknown.
The development efficiency result has not been confirmed by this suite; the
pooled operational advantage cannot erase the GLM functional regression.
See the [confirmation report](../../Evals/prompt-lab/results/native-confirmation-01/REPORT.md).

All 74 runtime sources, archives and the frozen bundle matched. The 107 captured
redacted system texts match the exact templates; one deadline outcome is absent.
After terminal verification, the unchanged baseline/compact comparison started
the 54 predeclared multi-file transfer cells in `native-transfer-01`. Its source
archive is also verified. The first GLM baseline inventory case hit the shared
4,096-output-token cap before editing; that original failure is retained. Final
interpretation still waits for transfer and the 18 context conditions.

Early transfer auditing also reproduced a normal-completion baseline CSV error:
DeepSeek/baseline/inventory-import/sample 2 splits lines on commas and rejects
the valid quoted item ID in `item_id,qty\n"b,c",0\n`, rather than importing one
record for `b,c`. Its original failed external grade remains unchanged. Two
recommendation cases reached the shared output cap before editing, and the
same budget-failure treatment applies to both arms. These initial cases do not
determine the transfer comparison. Evidence is hash-bound in
`native-transfer-01/failure-audit.json`; the frozen prompt is not revised.

DeepSeek/recommendation/inventory-import/sample 2 later exhibited the same
quoted-CSV defect. The same minimal in-memory-database counterexample fails
under both prompt arms, and both original grades remain unchanged.

Transfer scheduling stopped after 17 completed cells when GLM/recommendation
tree-report-cli/sample 0 produced an unterminated JSON `edit_file` argument at
exactly 4,096 output tokens. Tool validation failed, then Go rejected that
assistant history with HTTP 400 on the next call. Offline JSON parsing reproduces
the malformed argument; the generation finish reason is absent, so the exact
cap/truncation mechanism is not independently proven. The original operational
failure remains. No argument repair or source/prompt change was made.

The process explicitly stopped and drained pending work, then was verified
terminal. The exact unchanged invocation continues only the 37 unrun cells;
every completed failure remains. `continuations.json` binds the retained result
prefix and completed IDs; its byte hash is unchanged after continuation starts.
See `malformed-tool-diagnostic.json` and `failure-audit.json` in the transfer
directory. An observation timeout was not treated as process termination.


## Independent CSV transfer grading review

The existing read-only reviewer independently reproduced the minimal quoted-comma
CSV failure in Gemini/baseline sample 0 and GLM/recommendation sample 0; the frozen
reference imports one row with ID `b,c` and quantity zero. Primary grades stay
unchanged under the same criterion for both prompts. The task requests CSV,
permits nonempty IDs and specifies no dialect disabling quoting.
[RFC 4180 §2](https://www.rfc-editor.org/rfc/rfc4180#section-2) documents quoted
fields with embedded commas as a common convention, also supported by
[Python's CSV reader](https://docs.python.org/3/library/csv.html). RFC 4180 is
Informational rather than an Internet Standard; unspecified dialect remains a
disclosure limitation, not sufficient grounds here for post-result task removal.

The oracle stops at the first failed quoted-field assertion, so the later
transaction and CLI checks are unobserved for those failing states. A specific
counterexample does not establish failures of every requested behavior or prompt
causation. Hash-bound task/detail evidence and the review judgment are in
`Evals/prompt-lab/results/native-transfer-01/csv-format-review.json`. Transfer
collection and final interpretation remain incomplete.


## Complete ordinary reserved comparison

Transfer completed all 54 cells with a verified terminal exit before context
stress began. Its original 17-cell prefix remains unchanged and all 26 failures
are hash-audited. The frozen 74 runtime sources, archived copies and compiled
bundle match; 51 captured system texts match exact templates, while three
supervisor deadlines have no outcome/prompt evidence. Baseline completed 15/27
versus compact 13/27; saved code passed 16/27 versus 14/27.

The combined nine-task comparison is complete 162/162 with all 34 failures audited.
Primary operational success is 64/81 for each prompt; saved code passes are 67/81
baseline versus 65/81 compact. Equal-model task-cluster quality delta is 0.00
percentage points, exploratory interval −6.17–6.17. Conditional successful-pair
token ratio is 0.999327 (0.860771–1.154257), call ratio 1.023200
(0.964480–1.070310); resources cover six common task clusters while quality
retains all nine. Missing usage/cache data prevent complete all-attempt and
three-model tariff comparisons. The development efficiency gain is unconfirmed.

The post-freeze keyed-window sensitivity also removes a genuine compact
boundary bug and cannot replace primary quality. CSV grades remain primary
following independent review; fail-fast checks do not establish later behavior
for failing states. No prompt, task or failed run was rewritten. Evidence:
`Evals/prompt-lab/results/native-transfer-01/REPORT.md`,
`results/native-heldout-comparison-01/REPORT.md` and `analysis.json` under the
prompt lab. Beginning-position stress is complete at six conditions: baseline 3/3 and
compact 2/3 operational successes, with all six saved code states passing. The
compact Gemini deadline is audited; its outcome/usage is unavailable. All 75
archives and five captured templates match. The middle position is live; the
end position and final selection/checks remain open. See
`Evals/prompt-lab/results/native-context-beginning-01/REPORT.md`.


## Final context results and practical choice

All 18 frozen context conditions are complete. Beginning has 3/3 baseline and
2/3 compact operational successes; middle and end each have 2/3 for both.
Code passes total 7/9 baseline versus 8/9 compact. All five failures retain their
original grades and hash-bound audits. The end-position malformed-JSON stop was
followed only after verified terminal state by four unrun cells; the original
two-row prefix remains byte-identical. All 75 common sources and 225 archive
copies match; all 17 captured system texts match, with one deadline outcome
explicitly unavailable. The same blocks render to 126,994 characters per
condition. This is one long-input task, not 18 independent tasks, a multi-turn
history study or a reproduction of Lost in the Middle.

The predeclared protocol allows retaining baseline if replacement is unjustified.
The ordinary tie, lower compact saved-code count, unknown efficiency advantage
and contextual tradeoffs support retaining baseline/standard without claiming
universal optimality or statistically proven superiority. The exact final
template is byte-identical to the tested baseline, SHA-256
`ba96623960bd530898ccd5e5be219f2f81b5c1a7b406db86eecbed7e3e15daa1`.
The earlier compact development freeze remains immutable. See
`Evals/prompt-lab/recommendation/FINAL.md`, `final-selection.json` and
`results/native-context-comparison-01/analysis.json` under the prompt lab.

Raw JSONL and per-run details remain intact locally and are excluded from Git
because native process failures retain generic toolchain metadata. Reports,
source archives, manifests, hashes and audits remain available. No publication
or product activation was performed. Final verification and closing independent
review remain open at this entry.


## Closing verification

`TAG_LIVE_TESTS=0 make check` exited zero after all live experiments were terminal.
It passed wiki lint, strict formatting/linting, build, 318 Swift tests and 91.5%
coverage of 6,968 lines against the unchanged 80% gate. All 42 offline reporting
tests passed. Fresh repeat and ordinary reserved reports reproduced every frozen
and final evidence hash exactly; the post-check bundle still matches the live
freeze. Generated OpenRouter dependency warnings are recorded without weakening
checks or changing the SDK.

An independent read-only closing review found no Important or Critical issue
and agreed that baseline retention follows the original protocol. It reproduced
the 812-run accounting, ordinary results and context hashes, including all five
failures and the retained end-position prefix. Minor stale README wording was
corrected without changing data or frozen assets. The bounded privacy check
found no active credential, actual home-prefix or hostname match in the scanned
task files; generic toolchain metadata remains only in Git-ignored immutable
raw traces. Verification, privacy and review receipts are under
`Evals/prompt-lab/recommendation/`.
