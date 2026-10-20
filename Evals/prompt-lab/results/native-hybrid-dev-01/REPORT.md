# Hybrid development result

All 24 cells were recorded with the frozen 98-word `adaptive_compact` policy:
12/12 successes on DeepSeek and 10/12 on GLM. The two retained GLM failures were
a reasoning-only response at the 4,096-token allowance before editing, and the
12-call limit after a Swift implementation that already passed external tests.
These are subject budget failures. Neither was regraded or retried.

The initial process ended after four cells on the empty actionable reply. After
terminal confirmation, the same manifest resumed only missing cells. Job IDs and
original outcomes remain unique and append-only.

The policy consumed 208,573 reported tokens / 73 calls on DeepSeek and 169,375
reported tokens / 74 calls on GLM. This exploration does not support promoting
the hybrid merely because its instructions are concise. Timing/cache state and
one sample per task limit comparative inference. Follow-up selection still needs
repetitions and unused confirmation tasks.

`analysis.json` and `results.jsonl` preserve the complete outcomes. The original
raw empty-reply status remains; subsequent controller versions classify the same
observable cap-exhaustion pattern as a subject generation limit so it does not
abort unrelated scheduled cases. It remains a failed attempt.
