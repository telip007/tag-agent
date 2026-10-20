# Exact tested system-text templates

Twelve tested policy/scaffold combinations extracted from native Agent system messages. Filling environment/project fields reproduced all 280 completed exploration prompts exactly. No winner is selected here.

| Template | General-rule words | Static prefix characters | Verified prompts |
| --- | ---: | ---: | ---: |
| [adaptive_compact](adaptive_compact.system-prompt.txt) | 98 | 1451 | 24 |
| [baseline](baseline.system-prompt.txt) | 118 | 1477 | 24 |
| [baseline_lean](baseline_lean.system-prompt.txt) | 118 | 1101 | 22 |
| [combined](combined.system-prompt.txt) | 476 | 3935 | 24 |
| [compact](compact.system-prompt.txt) | 63 | 1193 | 24 |
| [compact_lean](compact_lean.system-prompt.txt) | 63 | 817 | 22 |
| [evidence](evidence.system-prompt.txt) | 146 | 1715 | 24 |
| [evidence_lean](evidence_lean.system-prompt.txt) | 146 | 1339 | 22 |
| [examples](examples.system-prompt.txt) | 208 | 2095 | 24 |
| [minimal](minimal.system-prompt.txt) | 5 | 778 | 24 |
| [minimal_lean](minimal_lean.system-prompt.txt) | 5 | 402 | 22 |
| [workflow](workflow.system-prompt.txt) | 112 | 1547 | 24 |

`MANIFEST.json` records rules, scaffold, exact UTF-8 hashes and hashed trajectory evidence. Text files have no added final newline. The native identity/tool/rule prefix is exact. Fill environment and project fields; omit the final project block when AGENTS.md content is absent, matching the native renderer.

Supply the five actual native API tool definitions separately; a prose tool list does not provide function-calling schemas. Lean omits that prose list and retains every tool guideline. The research controller reproduces these treatments through core/scaffold selection.

The minimal general policy contains **five whitespace-separated words**. Its complete system text also includes native tool guidance and session/project fields. These lengths are not model tokens, full context size or tariff costs. No host path or machine environment is embedded.
