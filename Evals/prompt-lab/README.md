# Prompt lab

Final result: [retain baseline/standard](recommendation/FINAL.md). The exact
[final template](recommendation/final-system-prompt.template.txt) and
[machine-readable choice](recommendation/final-selection.json) are available.
All 162 ordinary reserved cells and 18 separate context conditions are complete;
the compact development winner did not confirm a replacement advantage.
Local checks passed: 318 Swift tests, 91.5% coverage and 42 offline tests;
see the [verification receipt](recommendation/verification.json) and
[closing review](recommendation/final-review.json).

Research utilities for Tag's system prompt. The next-action screen
(`benchmark.py`) sends native function-calling requests and grades the reply
without executing returned actions. The full-trajectory runner (`trajectories.py`)
executes the actual Tag Agent and built-in tools in synthetic fixture repositories,
then grades saved files with external tests. See the
[research and experiment plan](../../wiki/designs/prompt-optimization.md).

Uses Python 3's standard library and the existing `OPENCODE_API_KEY` environment
variable or Tag credential store. It never persists the key or HTTP error bodies.
The screen sends public prompt text and synthetic conversation data. Native
runs also send Tag's probed session environment and synthetic fixture content.

```sh
python3 -m unittest discover -s Evals/prompt-lab -v
python3 Evals/prompt-lab/benchmark.py --output Evals/prompt-lab/results/dev-01
```

The second command is a dry run. Add `--run` to use the existing Go allowance.
Use `--task read-before-edit --candidates baseline` for connectivity checks.
The initial model IDs come from live model discovery; they are provider aliases,
not immutable checkpoints. The default screen has 144 requests. Default
completion cap: 2,048 tokens/request; temperature: 0; two concurrent requests.
Reasoning settings remain provider defaults and may vary between models.

Each output directory contains an immutable experiment fingerprint and manifest,
append-only raw result rows, and a derived summary. Identical invocations resume
missing jobs; failed jobs are retained and not silently retried. Modified runners,
fixtures, settings or prompt text require a fresh directory. Auth/allowance errors
stop scheduling after the current bounded batch. Network timeouts are recorded
as infrastructure errors, not model behavior.

Compare within the same model. Tool definitions, environment and tasks are common
to all candidates; only general rules vary. Scheduling uses a fixed shuffled
order. The baseline manually mirrors `SystemPrompt.swift` and shipped tool rules;
the manifest records the source revision/hash. This copy needs verification after
production prompt changes. This utility does not invoke Tag's Swift adapters,
loop or tools; the screen cannot certify those components.

Task-specific graders require native tool calls with valid argument types and
selected path/command patterns, or a text answer with selected phrases. Compatible
inspection calls are accepted for selected tasks. These are preferred-action
scores; a different reasonable inspection sequence can still fail the rubric.
They do not execute code, prove all answer semantics, detect all malicious
commands, or evaluate full explanations. Inspect raw responses and investigate
false positives before expanding the suite. The few-shot candidate uses policy
examples rather than full native-call demonstrations; it is not a MIPRO run.

Reported usage is provider-reported, not locally tokenized. Monetary cost remains
unknown in the summary; tokens cannot establish cash charges or subscription
allowance consumption. Wall time includes provider/network latency and is
observational, not a controlled speed comparison. Do not treat repeated samples
of one task as independent evidence. Do not choose a winner on development
results alone. Freeze finalists before evaluating `--split holdout`; once used
for revision, that split is no longer held out.

```sh
python3 Evals/prompt-lab/report.py Evals/prompt-lab/results/dev-02
```

This validates the frozen manifest and result-job identities, reports missing
work, and computes exploratory paired differences against the baseline by
resampling whole tasks. The intervals are unadjusted for candidate selection or
multiple comparisons and are not confirmatory evidence.

The completed first screen and its raw-response audit are in
[the development report](results/dev-02/REPORT.md). Its scores have known
measurement limits and do not select a production winner.

`connectivity-01` records the initial two-request smoke test. `dev-01` is an
interrupted diagnostic run: synthetic assistant history omitted DeepSeek's
required reasoning replay field. Its infrastructure failures and initial stricter
rubrics must not be compared with `dev-02`. The fresh `dev-02` manifest includes
empty reasoning fields for synthetic history (no invented rationale), permits
reasonable inspection alternatives, and stops on any HTTP client error. All
candidate prompt text remained unchanged during these evaluator repairs.

## Native full trajectories

`trajectories.py` invokes the opt-in `PromptBenchmarkLiveTests` Swift bridge.
The bridge uses the real `Agent`, built-in tools and OpenCode Go adapter. Only
its general system rules vary. Baseline uses the exact production renderer;
policy tests verify the other prompt sections survive replacement. A scripted
loop test verifies the inference-call limit stops the actual Agent.

Build and validate the bridge before a live experiment:

```sh
TAG_LIVE_TESTS=0 swift test --filter PromptBenchmarkPolicyTests
python3 Evals/prompt-lab/trajectory_fixtures.py
python3 Evals/prompt-lab/trajectories.py --candidates baseline --task clamp --output Evals/prompt-lab/results/native-smoke-02
```

Add `--run` to the last command for live requests. The default full development
comparison selects baseline/compact/evidence across 12 complete tasks and two
models. `--repeats 3` expands it to 216 independent fixture runs. All generation
uses the common token cap/temperature; provider reasoning defaults remain.
Each job has a model-call limit and an external process-group deadline. The
native bridge is disabled in normal tests unless `TAG_PROMPT_JOB` is supplied.

The supervisor discovers the compiled bundle and local Swift test helper and
sets that helper's required XCTest framework/library search paths. It bypasses
SwiftPM's package lock so two fixture jobs can actually run concurrently. This
route currently requires macOS/Xcode. Build flags and the helper are not product
CLI options. The manifest pins source hashes and the compiled test-bundle hash;
rebuilding the bundle requires a new experiment directory.

Ten coding fixtures include Python, shell and Swift. Their external oracles were
checked against failing supplied code and passing reference repairs before live
use. Two further fixtures measure read-only answering and an explicit request to
clarify a business policy. Their final-text graders are weaker semantic evidence
than functional tests. Reference repairs and external assertions stay out of the
subject's fixture; this is not an access-control boundary on the shared host.
The benchmark is for ordinary synthetic coding tasks, not adversarial execution.

Each `runs/*.json` saves the outcome, individual model replies/usage, actual tool
outputs, final fixture text and external grader output. Existing tests, unrelated
notes and project instructions must remain unchanged. New generated files are
retained when readable and small; binaries and `.git`/bytecode are excluded.
Paths and host OS metadata are redacted structurally before JSON serialization.
An explicit code-test pass and a normal end to the agent turn are required for
success; a model's claim that tests passed is not sufficient. The raw trajectory
also records whether the documented visible check command was observed, although
that string match is an auxiliary metric rather than functional proof.

The initial native smoke failed in result sanitization. It is retained separately
with its limitation recorded; it provides no reliable quality comparison.

`native-dev-01` stopped after 20/72 jobs, with 18 successful completions and two
timeouts. A reconstructed follow-up also exposed a native interleaved-reasoning
encoding defect; see its [report](results/native-dev-01/REPORT.md). The encoding
repair changes the native harness fingerprint, so subsequent comparisons use a
fresh directory. [DeepSeek documents](https://api-docs.deepseek.com/guides/thinking_mode/)
that thinking mode ignores temperature: zero is requested, not guaranteed.

`confirmation_fixtures.py` contains six reserved functional tasks, with their
definitions, reference repairs and oracle validation frozen in
`results/confirmation-reserve-01/`. They were frozen before selection and model
access; post-freeze results are tracked in `results/native-confirmation-01/`.

## Candidate selection and resources

The [selection protocol](selection-protocol.md) records the comparison and confirmation procedure before opening reserved results. Custom policy files can be supplied with `--policy-file`; they cannot overwrite baseline or another existing policy. `--repeat-offset` gives follow-up samples distinct identities. `--suite confirmation` validates task definitions against the reserved manifest; a dry run sends no task requests.

`native_report.py` retains original scores and reads optional hashed behavioral adjudications separately. Explicit selection requests such as “Please choose” satisfy clarification without requiring a question mark. The original run rows are preserved. Code-test failures cannot be changed through that review path.

Resource reporting separates cached input, uncached input and output. The dated Go rate card yields recorded-usage allowance-rate estimates, with a DeepSeek peak/off-peak range. It does not establish cash charges or actual allowance debits; missing responses or cache data remain unknown.


## Whole-template ablation

`--scaffold lean` changes the research wrapper identity to
`You are Tag, a coding agent.` and removes the prose `<tools>` list. It
preserves core/tool rules, environment and project instructions, plus every
actual API tool schema and implementation. `standard` remains the default;
its native baseline is byte-for-byte unchanged. Lean sample labels gain
`_lean` so observations cannot be silently pooled under a standard identity.
The manifest records scaffold and source/bundle fingerprints.

[Structural treatment and checks](scaffold-ablation.md),
[completed core exploration](results/native-family-comparison-01/README.md),
and [development shortlist](proposals/development-shortlist.json) document the
completed comparisons and their predeclared selection plan. The config-precedence float ambiguity is documented
in that report: original failure preserved, whole-task exclusion uniform.
The development choice and subsequent confirmation are recorded separately;
no final adoption decision follows from this ablation alone.

`python3 Evals/prompt-lab/confirmation_report.py` audits the two ordinary
reserved suites against the immutable recommendation freeze. It preserves all
nine tasks in the primary analysis, labels the audited keyed-window whole-task
sensitivity as post-freeze, and reports missing suites, incomplete coverage and
unaudited failures explicitly. The output is
`results/native-heldout-comparison-01/analysis.json`; context conditions remain
separate. A partial report cannot establish the final recommendation.


`--scaffold both` interleaves standard and lean variants in one shuffled native
schedule. `policy_scaffolds` records the actual treatment per candidate and
`workers` pins concurrency in new manifests. A custom policy may instead fix
`"scaffold": "lean"` or `"standard"`; with the default global selection this
compares the unchanged native baseline directly with one frozen template.
The joint scheduler reserves `_lean` suffixes to prevent label collisions.
Known timeout/connection-loss outcomes remain failed, while other scheduled
cells continue; three consecutive provider errors still stop scheduling, and
authentication or unexpected failures remain fatal. Failed cells never retry.

The [repeated design](proposals/repeated-comparison.json) completes three samples
for each of four core policies × two scaffolds × two models × eleven tasks.
Sample zero is reused once from compatible archived experiments; the new
interleaved run adds samples 1 and 2 (352 fresh trajectories), for 528 selected
template trajectories overall. Source/bundle hashes and full outcomes remain
per run. The ordinary Go aliases do not pin immutable model weights.

The [complete repeated comparison](results/native-repeat-comparison-01/README.md)
verifies all 528 selected cells. Reproduce its strict sample-zero/repeat selection
with `python3 Evals/prompt-lab/repeat_selection.py` from the repository root.
The [development recommendation](recommendation/REPORT.md) retains uncertainty
and is frozen before reserved confirmation; it does not change production.

`--suite transfer` validates the three multi-file definitions against their
[reserved manifest](results/transfer-reserve-01/README.md). A dry run sent no
subject requests. The definitions were reserved before final selection and
remained unseen until the development recommendation/template freeze. All
54 cells are now complete; see the [transfer report](results/native-transfer-01/REPORT.md).

The fixed context stress treatment uses `--suite transfer --task framed-client
--context-position beginning` (or `middle`/`end`), with one sample at offset zero.
Each position uses a separate output directory and immutable reserve validation;
the family reporter rejects pooling different contexts. The original task and
external oracle stay unchanged. Omitting the flag preserves exact task text.


[Exact tested template catalogue](templates/README.md): twelve system-text
templates with hashes, general rules, scaffold metadata and dynamic environment/
project fields. Filling those fields reproduces all 280 completed exploration
prompts exactly. The catalogue preserves all tested variants; the completed
[reserved comparison](results/native-heldout-comparison-01/REPORT.md),
[context stress](results/native-context-comparison-01/REPORT.md) and
[final choice](recommendation/FINAL.md) provide the subsequent decision.

## Local raw evidence

The immutable append-only `results/**/*.jsonl` files and per-run `runs/` details
remain available in this local workspace and are excluded from Git. Native
process/tool failures can retain generic toolchain paths and platform metadata.
Their hashes, failure audits, frozen manifests, source archives, exact template
assets and derived reports remain available. Do not rewrite historical raw
records to make them shareable: any future publication needs a separate reviewed
redacted projection with provenance. The local benchmark results do not imply
that raw traces were published.

Source archives in this study were copied and hash-verified explicitly from
each frozen manifest. The supervisor records source hashes but does not
automatically create the `source/` copies. For a fresh study, copy each listed
repository-relative source to `OUTPUT/source/RELATIVE_PATH` while the pinned
source tree is unchanged and verify its SHA-256 against the manifest. The
ordinary reserved report requires these archives; the native per-run reporter
verifies them when present.
