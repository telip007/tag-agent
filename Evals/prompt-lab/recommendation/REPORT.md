# Development recommendation — confirmation pending

The selected candidate is **compact with the standard native scaffold**.
`policy.json` contains its exact five general rules; `system-prompt.template.txt`
contains the exact tested system-text template, including native identity,
prose tool list and tool-use guidance. Fill the explicit environment and project
fields as described in `../templates/README.md`; provide the five actual API tool
schemas separately. The general rules contain 63 whitespace-separated words.

It completed 66/66 selected development trajectories, compared with 64/66 for
baseline. Evidence/lean also completed 66/66, but compact used fewer total
tokens and lower recorded-usage rate values on both development models. The
task-balanced conditional token ratio against baseline is 0.951 (exploratory
95% interval 0.860–1.051), and the conditional rate-value ratio is 0.992
(0.896–1.087). These uncertain comparisons do not establish a cost reduction
or a universal optimum. See `../results/native-repeat-comparison-01/README.md`
and `selection.json` for all eight templates and retained failures.

`FREEZE.json` binds the exact assets, decision evidence and reserved suite
fingerprints before any reserved subject request. It must remain immutable.
The next step is unchanged baseline versus this fixed recommendation on six
confirmation and three multi-file transfer tasks, three samples on each of
DeepSeek, GLM and Gemini (162 trajectories), then the 18 predeclared context
conditions. No tuning on those results preserves their held-out status.

The production system prompt is unchanged. This is a research recommendation
awaiting confirmation, with no push, publication or activation performed.
