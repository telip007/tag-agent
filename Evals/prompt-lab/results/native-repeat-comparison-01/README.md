# Repeated template comparison

The predeclared matrix is complete: **528 trajectories**, four core policies ×
two scaffolds × two development model aliases × eleven tasks × three samples.
Sample zero comes from the previously declared runs once; samples one and two
come from the completed interleaved repeat run. The ambiguous config task is
excluded uniformly. `selection.json` verifies exact coverage, origins, task and
policy hashes, and preserves all failures. `analysis.json` additionally retains
all 632 exploration/ablation/repeat trajectories as a sensitivity view.

| Template | DeepSeek success | GLM success | Task-balanced token ratio | Task-balanced rate-value ratio |
| --- | ---: | ---: | ---: | ---: |
| baseline | 32/33 | 32/33 | 1.000 | 1.000 |
| baseline/lean | 33/33 | 31/33 | 0.922 | 0.955 |
| compact | 33/33 | 33/33 | 0.951 | 0.992 |
| compact/lean | 33/33 | 31/33 | 0.856 | 0.920 |
| evidence | 33/33 | 31/33 | 0.980 | 0.981 |
| evidence/lean | 33/33 | 33/33 | 0.979 | 0.986 |
| minimal | 33/33 | 31/33 | 0.923 | 1.018 |
| minimal/lean | 33/33 | 30/33 | 0.826 | 0.981 |

Ratios condition on paired successful runs with complete usage. Repeats are
averaged within task/model, then models receive equal weight; confidence
intervals resample whole tasks. They are exploratory and unadjusted for
selection. Compact's token ratio interval is 0.860–1.051 and its rate-value
interval is 0.896–1.087. Neither establishes a resource gain. Its quality
difference against baseline is +3.03 percentage points with an exploratory
interval of 0–7.58; this is not proof of universal superiority.

Compact/standard and evidence/lean each succeeded 66/66. Compact used fewer
all-attempt tokens and lower all-attempt rate values on both models than
evidence/lean: 446,615 versus 460,906 tokens on DeepSeek and 432,371 versus
527,571 on GLM. All usage for these two candidates is complete. Conditional
rate ratios have a small opposing tradeoff; cache/routing were uncontrolled.
Compact/standard is therefore the practical development choice for reserved
confirmation, with the uncertainty retained. Shorter lean candidates' budget
failures are not erased by conditional savings. Minimal/lean also contains a
normal-completion functional error. No final adoption is implied.

The 352 fresh repeat cells achieved 345 reviewed operational successes (344
raw). Of 288 saved coding states, 284 passed external tests; all 64 behavioral
cases passed after one separate hashed Markdown-choice adjudication. Three
call-limit failures had correct saved code; three generation caps did not.
One normal-completion Swift digit error remains a genuine failure. There were
2,036 attempted model calls and 4,734,047 provider-reported tokens. All 352
outgoing system texts match the fixed catalogue; all eight raw failures have
hash-bound author audits. See `../native-repeat-dev-01/`.

Reproduce the strict selected matrix from the repository root:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 Evals/prompt-lab/repeat_selection.py
```

The exact recommendation and pre-confirmation freeze live in
`../../recommendation/`. The nine reserved tasks and context stress remain
separate post-freeze checks. Synthetic fixtures, mutable model aliases, finite
tests and uncontrolled routing/cache limit generalization. Cash charges and
actual allowance debits remain unknown.
