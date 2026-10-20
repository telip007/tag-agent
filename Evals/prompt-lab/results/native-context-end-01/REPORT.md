# Context stress: task at end

Complete: six conditions on the same frozen framed-client task and unchanged
archive/task blocks (126,994 characters). Both prompts pass on DeepSeek and
Gemini. GLM baseline fails after malformed JSON tool arguments at the shared
output cap are replayed and rejected with HTTP400; GLM compact reaches the
12-call limit after saving externally correct code. Each prompt has 2/3
operational successes; saved code passes are 2/3 baseline and 3/3 compact.

The first process explicitly stopped scheduling after the malformed-history
error and drained pending work. After verified exit, an unchanged invocation
continued only four unrun cells. Both original rows and their failure remain
byte-identical, bound by `continuations.json`. No failed cell was retried, no
argument repaired and no prompt, budget or runtime changed. The cap is consistent
with truncation, but the exact mechanism is not independently proven without
a captured finish reason. Both failures are hash-audited.

All six captured system texts match their fixed templates; all 75 source archives
match. Recorded usage is 1,436,919 tokens and 38 attempted calls, lower bounds because
the failed fifth GLM baseline request has no returned usage. The continued
process exited zero and its PID was verified absent before final analysis.
See `analysis.json`, `template-verification.json`, `failure-audit.json` and
unchanged local raw data. This remains one task with one attempt per condition;
no causal position effect or universal superiority is inferred.
