---
title: Research on agent context management
summary: Eight primary papers support reversible evidence storage and simple baselines while warning that trained memory policies and benchmark gains do not transfer automatically to Tag.
updated: 2026-10-20
---

# Research on agent context management

Read on 2026-10-20 for the [native Tag proposal](../designs/native-context-management.md).
These are selected relevant papers, not a systematic literature review.
Versions and [capture links](../raw/2026-10-20-context-mode.md) are pinned;
all proposed Tag adaptations below are our inferences. No paper experiment
was reproduced and no reported gain is a Tag result.

| Paper and inspected sections | Evidence and limits | Inference for Tag |
| --- | --- | --- |
| [The Complexity Trap, 2508.21433v1](https://arxiv.org/html/2508.21433v1), §§3–6, Table 1, Appendix D | Compares raw history, observation masking and LLM summaries in SWE-agent on SWE-bench Verified across five configurations. Masking is strongly competitive; the best method varies by configuration. Table 1 gives Qwen3-Coder solve rates of 53.4% raw, 54.8% masked, 53.8% summarized, with overlapping intervals. Summaries can prolong trajectories; omitting observations still leaves other history growing. The abstract's raw figure differs from Table 1; use the table. | Include masking as a serious low-complexity baseline, retain failure evidence, measure whole-task cost and do not infer bounded history from masking alone. |
| [CodeAct, 2402.01030v4](https://arxiv.org/html/2402.01030v4), §§2–3 | Executable Python actions support loops, composition and corrective execution feedback; evaluations include 17 models and M³ToolEval. Reported benefits depend on models and tasks, with larger gains for stronger models. This does not compare native Swift tool admission policies. | Use scripts for exact aggregation instead of asking the LLM to count or join raw data. Keep ordinary file/edit tools and execution errors available; test rather than mandate code-only actions. |
| [MemGPT, 2310.08560v1](https://arxiv.org/html/2310.08560v1), §§2–3, §5.1 | Separates limited main context from external memory and uses explicit editing, retrieval and control flow. Evaluations concern conversation and document analysis, not repository patch acceptance. | Separate durable evidence from active context. A small current-task record and paginated retrieval are architectural precedents, not proof of native coding quality. |
| [ReWOO, 2305.18323v1](https://arxiv.org/html/2305.18323v1), §§3–4 | Separates planning, tool acquisition and solving using evidence references; evaluates NLP reasoning, including HotpotQA. Plans made before observations have different constraints from interactive debugging. | Batch independent read operations and keep their intermediate payloads out of the prompt; retain sequential observe–repair feedback for dependent operations and side effects. |
| [Context-Folding, 2510.11967v1](https://arxiv.org/pdf/2510.11967v1), §§2–4, Table 2 | Branch/return removes subtask detail from active context while keeping an outcome. FoldGRPO trains this behavior with process rewards; reported context reductions accompany that trained setup. | Later test bounded subtask scopes with evidence-linked return records. Adding a branch tool to arbitrary providers does not reproduce trained folding. |
| [Recursive Language Models, 2512.24601v1](https://arxiv.org/html/2512.24601v1), §§2–5 | Places the input in a REPL and examines it programmatically, optionally through sub-LM calls. Experiments cover long-input tasks including repository understanding, not full coding-agent repair sessions. The paper documents redundant calls, variable cost and implementation limits. | Separate sparse lookup from dense analysis: search for a fact, but scan all records when computing an aggregate. Recursive model calls are an optional later experiment with depth, call, token and time caps. |
| [ACE, 2510.04618v3](https://arxiv.org/html/2510.04618v3), §3, §4, Table 18 | Uses itemized playbooks, localized delta updates and refinement rather than repeated full rewrites; evaluates AppWorld and domain reasoning. Its adaptation objective differs from compressing raw tool output. | Update individual task-state facts with provenance and explicit supersession. Treat any learned playbook separately from user instructions; do not let retrieved data rewrite project policy. |
| [ACM, 2607.23809v1](https://arxiv.org/html/2607.23809v1), §§3–6, Appendix D | Gives agents context-editing and recall tools, preserving offloaded raw messages, and develops post-training data. Experiments include coding and search; smaller thinking-model case studies fail to use management tools effectively. “Lossless” concerns preservation, not guaranteed retrieval or reasoning. | Combine optional model hints with deterministic host limits. Benchmark untrained management separately from post-trained results; make every evicted record exactly recoverable without requiring a clever recall query. |

## Synthesis

Three different mechanisms should be evaluated separately: reducing what
enters context, changing old working context, and learning reusable
strategies. They have different correctness, latency and cache costs.

The evidence favors a staged comparison over a single elaborate memory
system. Start with deterministic admission and exact retrieval, compare
simple masking, and add selective summaries or scoped subtask returns only
when measured failures justify them. Keeping raw bytes makes a reduction
reversible; it does not guarantee that the model asks the right question.
An explicit exact-read path and coverage-aware analysis are therefore core
parts of the [proposal](../designs/native-context-management.md).
