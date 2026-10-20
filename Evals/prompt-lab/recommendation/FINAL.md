# Measured system-prompt recommendation

**Retain baseline with Tag's standard native scaffold.** The compact candidate
won development selection but did not establish a reliable quality/efficiency
advantage in reserved validation. This is a practical decision for the measured
distribution, not proof that baseline is universally optimal or statistically
superior. The search did not establish an “ultimate” prompt.

Use [the exact final system-text template](final-system-prompt.template.txt).
SHA-256: `ba96623960bd530898ccd5e5be219f2f81b5c1a7b406db86eecbed7e3e15daa1`.
It is byte-identical to the tested baseline catalogue entry, with no extra
newline or untested revision. [Machine-readable decision](final-selection.json).
Fill `{{environment}}` and `{{project_instructions}}` as described in the
[template catalogue](../templates/README.md), omitting the final project block
when absent. Supply the real five API tool schemas separately. Production
`SystemPrompt.swift` already renders this policy and was not changed.

Its six general rules contain 118 whitespace-separated words:

```text
- Read the relevant code before changing it.
- Write the simplest code that solves the task: no features, abstractions or options nobody asked for.
- Change only what the task needs, and match the surrounding code's style. Mention unrelated problems you notice instead of fixing them; remove only what your own change left unused.
- After changing code, run the project's build or tests and read the result. If you couldn't, say so.
- Ask before destructive or outward-facing actions (deleting files, git push, anything outside the project). If a request can be read several ways, name the readings and ask instead of picking one silently.
- Finish with 2–4 sentences: what changed, how you checked it, what's left. Name files by path.
```

The full template also preserves native identity, tool descriptions and tool-use
guidance. These core rules alone are not the complete tested system text.

## What was tested

Eight cores: baseline, compact, workflow, evidence-gated effort, short examples,
combined, adaptive_compact and a five-word minimal control. Four cores also had
a lean scaffold, giving twelve exact tested templates. Lean shortened identity
and omitted the redundant prose tool list while keeping API tools, native tool
guidelines, environment and project instructions. The adaptive 98-word proposal
combined concise scope, evidence, trust and stopping rules; it was an experimental
combination, not a literature novelty claim.

| Phase | Native trajectories | Purpose |
| --- | ---: | --- |
| Eight-core exploration | 192 | General policy comparison |
| Standard/lean scaffold ablation | 88 | Whole-template representation |
| Fresh interleaved development repeats | 352 | Stability and paired resources |
| Six reserved functional tasks | 108 | Frozen candidate confirmation |
| Three reserved multi-file tasks | 54 | API/CLI and two-module transfer |
| Context-position stress | 18 | One task, three block positions |
| Total main native trajectories | 812 | Excludes screen, smokes and interrupted diagnostics |

The strict 528-cell repeated selection matrix is a subset/reuse of development
data above, not another 528 new runs. It has four cores × two scaffolds × two
models × eleven tasks × three samples. The separate 144-response decision
screen did not execute returned actions and did not select a coding winner.

Development models were DeepSeek V4.1 Flash and GLM 5.3 Flash. Reserved validation
added Gemini 4 Argon Contributor, using the real Tag loop, adapters and tools.
These are mutable Go aliases across two native wire formats, not pinned model
weights or a complete frontier/small-model matrix. Controls: 12 calls per job,
4,096 output tokens per inference, 180 seconds per job, two workers, requested
temperature zero, provider reasoning defaults. DeepSeek thinking mode can ignore
temperature. Source/bundle hashes and exact policy/task identities are retained
per experiment; earlier development bundles differ as documented.

Engineering work adds an opt-in Swift benchmark bridge and Python fixtures,
controllers and reports. A necessary production ChatCompletions compatibility
repair replays the configured reasoning field (or an empty value when absent),
without inventing reasoning or leaking it into an unrelated wire format.
Regression tests and the required repository check cover that repair. The
production general rules and system renderer remain unchanged.

## Results and decision

Compact/standard reached 66/66 selected development successes, baseline 64/66.
Evidence/lean also reached 66/66 but consumed more total recorded tokens and
rate-card usage on both development models than compact/standard. That selected
compact before any reserved request. Its conditional development token ratio
was 0.951 (0.860–1.051), not a proven saving. The immutable
[development freeze](FREEZE.json) and [original decision](REPORT.md) remain
unchanged, including their historical confirmation-pending status.

| Ordinary reserved validation | Baseline | Compact |
| --- | ---: | ---: |
| Successful agent turns | 64/81 | 64/81 |
| Externally passing saved code | 67/81 | 65/81 |
| DeepSeek successful turns | 22/27 | 24/27 |
| GLM successful turns | 20/27 | 18/27 |
| Gemini successful turns | 22/27 | 22/27 |

All 162 ordinary cells are complete and all 34 failures hash-audited. Primary
quality retains all nine tasks. The paired equal-model quality difference is
0.00 percentage points, exploratory 95% interval −6.17–6.17. Neither equivalence
nor causal superiority follows from that interval. Conditional successful-pair
token ratio is **0.999327 (0.860771–1.154257)**; call ratio is
**1.023200 (0.964480–1.070310)**. Resources cover six common task clusters,
while quality retains nine. These are not all-attempt cost savings. Complete
three-model tariff and several all-attempt cost-per-success values are unknown.
See the [ordinary reserved report](../results/native-heldout-comparison-01/REPORT.md).

All 18 context conditions are complete, with all five failures audited. Descriptive
operational totals are baseline 7/9 versus compact 6/9; saved-code passes are 7/9
versus 8/9. Thus the context results also show a tradeoff, not uniform dominance.
The identical 125,952-character archive is reordered around one unchanged task;
all rendered messages have 126,994 characters. Positions and models do not create
independent task samples, so no task-bootstrap interval or position-causation
claim is made. This is a single long-input task, not a multi-turn-history study.
See the [context report](../results/native-context-comparison-01/REPORT.md).

The predeclared [selection protocol](../selection-protocol.md) permits baseline
fallback when a replacement is not justified. Compact cuts general-policy word
count by 46.6%, yet its reserved conditional token saving is unconfirmed, GLM's
observed operational score is lower, and ordinary saved-code passes favor
baseline. Retaining the existing policy is the evidence-supported practical
choice. This does not prove baseline intrinsically better on every model/task.
Compact remains the strongest development-selected new candidate, not a verified
universal replacement. No prompt was tuned on the reserved results. Any future
revision using them requires fresh unseen validation.

## Research translated into experiments

| Primary source | Applied idea and boundary |
| --- | --- |
| [The Prompt Report, §2](https://arxiv.org/html/2406.06608v1) | Separate workflow, examples and self-criticism instead of assuming a verbose combination wins. |
| [MIPRO, §3–6](https://arxiv.org/html/2406.11695v1) | Downstream development evaluation and a frozen validation split. No MIPRO optimizer or automatic demonstration search was implemented. |
| [GEPA, §3](https://arxiv.org/pdf/2507.19457v2) | Audited trajectory feedback informed manual proposals. GEPA's reflective optimizer and complementary instance-wise Pareto algorithm were not implemented; our quality/resource frontier is distinct. |
| [Self-Refine, §2–3](https://arxiv.org/html/2303.17651v2) | Test explicit verification while counting added calls. A rule to reflect is not the iterative Self-Refine algorithm. |
| [Cannot Self-Correct, §3–5](https://arxiv.org/html/2310.01798v2) | Prefer external tests/tool feedback to unsupported repeated self-assessment; no claim that all modern self-correction fails. |
| [Lost in the Middle, §2–3](https://arxiv.org/html/2307.03172v1) | Freeze a long-input position stress check. This coding task is not a reproduction of the paper's retrieval experiments. |

The repeat and ablation evidence argues for measuring complete agent work,
not choosing by instruction length or adding every technique. The lean/minimal
options sometimes save conditional resources but retain observed failures. The
small test distribution cannot establish that removed safety instructions are
unnecessary.

## Evidence and limits

All 58 raw failures in the main 812 trajectories are bound by the
[run-qualified failure index](../results/main-failure-audit.json), including
the eleven earlier failures previously explained in narrative reports.
Independent review verified exact coverage and unchanged statuses/grades.
All original grades remain. Code-test failures cannot receive behavioral pass
overrides. One development Markdown clarification false negative was corrected
separately with a hashed semantic review. The config-precedence float ambiguity
was excluded uniformly from development selection before the final choice;
raw failures and all-task sensitivity remain. The reserved keyed-window bool
sensitivity is post-freeze, removes a genuine compact boundary error as well,
and cannot replace primary quality. Quoted-CSV failures remain after independent
review; the fail-fast oracle does not establish later transaction/CLI behavior
for those failing states.

Ordinary and context validation recorded 8,182,974 tokens and 1,175 attempted model
calls, both lower bounds. Five supervisor deadlines have no outcome; other
failed requests lack usage. No actual cash charge or allowance debit is known.
All 175 captured system texts match exact templates; missing deadline texts are
not inferred. Malformed JSON argument replay is a retained runtime/model failure
at the common cap; exact truncation cause is not independently proved without
finish-reason capture. Explicit scheduling stops were followed only by verified
continuation of unrun cells with unchanged prefixes; failed cells never retried.

These are authored synthetic tasks, finite external assertions, mutable aliases,
uncontrolled cache/routing and exploratory intervals unadjusted for selection.
Repeats are not independent tasks. No protected existing-file changes were
observed. The fixture directories are not an adversarial sandbox. No SWE-bench
score, adversarial-security proof, complete wire transcript, broad model-tier
coverage or universal optimum is established. The scoped research bridge does
not implement the broader production CLI evaluation roadmap.

Raw JSONL/details remain intact locally and are excluded from Git because native
logs retain generic toolchain metadata. Manifests, hashes, audits, source archives
and reports remain available. No publication, push, service activation or
production prompt replacement was performed.

## Reproduction and verification

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s Evals/prompt-lab -v
PYTHONDONTWRITEBYTECODE=1 python3 Evals/prompt-lab/repeat_selection.py
PYTHONDONTWRITEBYTECODE=1 python3 Evals/prompt-lab/confirmation_report.py
TAG_LIVE_TESTS=0 make check
```

The [lab README](../README.md) documents exact live invocations, environment,
resumption and per-position audits. Re-running on mutable aliases gives a new
measurement, not the historical model checkpoint; identical frozen invocations
resume missing cells rather than retry recorded failures.

Required local verification passed: **318 Swift tests**, **91.5% coverage**
against the unchanged 80% gate, **42 offline Python tests**, and exact fresh
528-cell/162-cell report reproduction. Generated OpenRouter dependency warnings
remain documented; no check was weakened. The closing independent review found
no Important or Critical issue and supported baseline retention; stale README
wording was corrected. See [verification](verification.json),
[review record](final-review.json) and [bounded privacy check](privacy-audit.json).
