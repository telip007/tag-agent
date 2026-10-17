# Wiki index

Start here. Conventions: [SCHEMA.md](SCHEMA.md). Timeline: [log.md](log.md).

## Concepts

- [Backpressure setup](concepts/backpressure-setup.md): every automated check in this repo, where it runs, and the traps we hit wiring it up.
- [Agent workflow](concepts/agent-workflow.md): how hooks, skills, AGENTS.md and the wiki make every agent session follow the same rules.
- [OpenRouter SDK](concepts/openrouter-sdk.md): how Tag Agent consumes the swift-openrouter submodule and where its own docs live.

## Decisions

- [0001 Agent code is written by hand](decisions/0001-hand-written-agent-code.md): agents teach and review; the human writes `Sources/Tag`.
- [0002 Maximum backpressure](decisions/0002-maximum-backpressure.md): warnings are errors, strict lint, coverage gate, hooks.
- [0003 OpenRouter SDK as a separate repo and submodule](decisions/0003-openrouter-sdk-submodule.md): published on its own, developed in place.
- [0004 LLM-maintained wiki](decisions/0004-llm-wiki.md): project memory lives in `wiki/`, enforced by hooks.

## Sources

- [Don't waste your back pressure](sources/dont-waste-your-backpressure.md): Moss's essay on automated feedback as the lever for agent autonomy.
- [LLM wiki pattern](sources/llm-wiki-pattern.md): Karpathy's idea file for agent-maintained knowledge bases.
