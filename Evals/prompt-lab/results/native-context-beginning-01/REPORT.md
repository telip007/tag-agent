# Context stress: task at beginning

Complete: six conditions on the same frozen framed-client task. Two identical
archive blocks and the unchanged task render to 126,994 characters. Only block
order changes between positions; this is one authored task, not six independent
tasks or a reproduction of Lost in the Middle.

| Model | Baseline operational success | Compact operational success | Saved code passes |
| --- | ---: | ---: | ---: |
| DeepSeek | 1/1 | 1/1 | Both pass |
| GLM | 1/1 | 1/1 | Both pass |
| Gemini | 1/1 | 0/1 | Both pass |

Gemini compact hit the unchanged 180-second supervisor deadline after saving
externally correct code. Its operational failure remains; exact call count,
usage, captured system text and underlying provider/tool cause are unknown.
The hash-bound failure audit does not retry or override it. All other cells
finished normally and passed. Recorded usage is 1,683,620 tokens and 44 attempted
calls, both lower bounds; missing deadline usage is not zero. Timing remains
observational and one sample per condition cannot establish a position effect.

All 75 source archives match their manifest hashes, and all five captured system
texts match the fixed templates. The rendered task is 126,994 characters with the
reserved archive, task and renderer fingerprints. The supervisor exited zero
and its PID was verified absent before the middle-position run began. See
`analysis.json`, `template-verification.json`, `failure-audit.json` and raw data.
The ordinary 162-cell comparison is separate; other context positions and final
selection remain pending. No production prompt was replaced.
