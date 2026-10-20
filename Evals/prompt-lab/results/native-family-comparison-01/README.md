# Native policy-family comparison

This derived report combines the completed baseline/compact/evidence comparison,
the adaptive-compact exploration and the remaining policy-family run. It stays
explicitly incomplete until all 192 exploration cells exist. Native source and
bundle fingerprints are preserved per input run; this is exploratory pooling,
not a contemporaneous randomized comparison.

Primary development selection excludes `config-precedence` uniformly; the
original external failure remains in raw/all-task scores. See
[data-quality.json](data-quality.json) for the rationale and exact hashes.
No code-test grade is overridden.

Recompute from the repository root:

```sh
python3 Evals/prompt-lab/family_report.py Evals/prompt-lab/results/native-dev-02 Evals/prompt-lab/results/native-hybrid-dev-01 Evals/prompt-lab/results/native-family-dev-01 --exclude-task config-precedence --output Evals/prompt-lab/results/native-family-comparison-01/analysis.json
```

Resource ratios condition on successful, complete-usage task/repeat pairs,
with raw and reviewed failure counts reported separately. They must not be
read as end-to-end savings, causal prompt effects or invoice amounts.
The rate ratio uses a common same-model tariff scenario; actual DeepSeek
peak/off-peak timing is unresolved. Equal-model summaries display their
model count and pair coverage. Repetition and unused confirmation remain
required before recommending a replacement.
