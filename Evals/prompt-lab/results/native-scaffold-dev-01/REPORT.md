# Whole-template development ablation

Completed 88/88 trajectories across four cores, eleven unchanged development tasks and two models. Lean shortens identity and omits only the prose tool list; actual API tools, guidelines, environment and project instructions remain intact.

| Model | Core (lean) | Success | Calls | Reported tokens |
| --- | --- | ---: | ---: | ---: |
| deepseek-v4.1-flash | baseline_lean | 11/11 | 62 | 137,466 |
| deepseek-v4.1-flash | compact_lean | 11/11 | 58 | 120,278 |
| deepseek-v4.1-flash | evidence_lean | 11/11 | 65 | 155,617 |
| deepseek-v4.1-flash | minimal_lean | 11/11 | 63 | 144,502 |
| glm-5.3-flash | baseline_lean | 10/11 | 66 | 139,965 |
| glm-5.3-flash | compact_lean | 9/11 | 66 | 138,040 |
| glm-5.3-flash | evidence_lean | 11/11 | 69 | 199,057 |
| glm-5.3-flash | minimal_lean | 11/11 | 58 | 116,827 |

85/88 agent turns completed successfully. All 72 saved coding states passed external tests; one of those reached the twelve-call limit and remains an operational failure. The two other failures were network connections lost during behavioral tasks. All fourteen normally completed behavioral attempts passed their rubric.

The first controller stopped after 52 cells on the two network failures. Its terminal process and unchanged manifest were verified before resuming only the 36 missing cells. No failed cell was retried or replaced. Source snapshots (72 files), full rows and original failures are retained.

Total attempted model calls: 507; reported tokens: 1,151,752. Unreturned inference usage is unknown, so recorded usage is a lower bound rather than a billing receipt.

This single sample per task/model/template does not select a scaffold or prompt. Source/cache state and upstream aliases remain variable; workflow duration includes provider/network and grading overhead. The next repeated comparison interleaves all eight shortlisted standard/lean templates under one shuffled schedule with two workers, preserving repeat identities 1 and 2. Sample zero is counted once.

Confirmation and the new multi-file transfer reserve remain unused by subject models.
