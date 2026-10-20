# Remaining native policy-family exploration

Completed 96/96 trajectories: four policies × twelve development tasks × two models × one sample.

| Model | Policy | Success | Calls | Reported tokens |
| --- | --- | ---: | ---: | ---: |
| deepseek-v4.1-flash | minimal | 12/12 | 68 | 168,040 |
| deepseek-v4.1-flash | workflow | 12/12 | 69 | 189,703 |
| deepseek-v4.1-flash | examples | 12/12 | 74 | 217,380 |
| deepseek-v4.1-flash | combined | 12/12 | 69 | 212,798 |
| glm-5.3-flash | minimal | 11/12 | 67 | 131,043 |
| glm-5.3-flash | workflow | 12/12 | 82 | 200,822 |
| glm-5.3-flash | examples | 11/12 | 75 | 179,710 |
| glm-5.3-flash | combined | 11/12 | 74 | 204,269 |

93/96 end-to-end successes. Three original failures remain:

- GLM/combined/config-precedence: normal completion, external rejection of numeric `2.5`; the task does not specify numeric-float handling. Raw code-test failure preserved; whole task excluded uniformly from primary selection, with all-task sensitivity retained.
- GLM/examples/swift-chunks: twelve-call limit after a saved implementation that passed external checks.
- GLM/minimal/shell-log-count: a reasoning-only empty reply at the 4,096-output-token cap, with no repair and failing external checks.

There were no transport failures in this run. All 32 behavioral attempts passed their existing rubric. These are weaker semantic checks than the external code tests. Source snapshots (71 files) were verified against the frozen hashes before subsequent bridge changes. No failed cell was retried.

The five-word minimal general policy still retains native identity, tool summaries, tool guidelines, environment, project instructions and actual API tool definitions. It is not a five-word whole system prompt. Its budget failure prevents selecting it by prompt length alone.

Pooled development analysis, the fixture audit and source compatibility record are in `../native-family-comparison-01/`. These single-sample observations do not establish an optimum. Shortlisted cores require repetition and whole-template ablation before unused confirmation.

Documentation clarification: the minimal rule has five whitespace-separated
words. The previous prose used six; the tested text, hashes, grades and provider
token measurements are unchanged.
