# Wiki index

Start here. Conventions: [SCHEMA.md](SCHEMA.md). Timeline: [log.md](log.md).

## Concepts

- [Backpressure setup](concepts/backpressure-setup.md): every automated check in this repo, where it runs, and the traps we hit wiring it up.
- [Agent workflow](concepts/agent-workflow.md): how hooks, skills, AGENTS.md and the wiki make every agent session follow the same rules.
- [Agent loop and tools](concepts/tools.md): How the agent loop runs tool calls, the five built-in tools, and where they differ from their Go originals.
- [Terminal UI](concepts/terminal-ui.md): How the chat UI is built on Stipple: the design intent, the agent's event seam, the observable session, the view and its hidden keys, why it runs on the main actor, and how it is tested.
- [OpenRouter SDK](concepts/openrouter-sdk.md): how Tag Agent consumes the swift-openrouter submodule and where its own docs live.

## Decisions

- [0001 Agent code is written by hand](decisions/0001-hand-written-agent-code.md): superseded by 0006.
- [0002 Maximum backpressure](decisions/0002-maximum-backpressure.md): warnings are errors, strict lint, coverage gate, hooks.
- [0003 OpenRouter SDK as a separate repo and submodule](decisions/0003-openrouter-sdk-submodule.md): published on its own, developed in place.
- [0004 LLM-maintained wiki](decisions/0004-llm-wiki.md): project memory lives in `wiki/`, enforced by hooks.
- [0005 Tag and TagKit targets](decisions/0005-tag-and-tagkit-targets.md): a thin executable over a testable library.
- [0006 Agents build the harness](decisions/0006-agents-build-the-harness.md): after the hand-written first loop, agents write `Sources/` code too.
- [0007 Conventional Commits](decisions/0007-conventional-commits.md): Commit messages and PR titles use the same Conventional Commits format as the SDK; no release tooling yet.
- [0008 Stipple for the terminal UI](decisions/0008-stipple-terminal-ui.md): The chat UI is a Stipple view instead of print/readLine with raw ANSI escapes, and the views live in TagKit so they can be tested.

## Sources

- [Don't waste your back pressure](sources/dont-waste-your-backpressure.md): Moss's essay on automated feedback as the lever for agent autonomy.
- [LLM wiki pattern](sources/llm-wiki-pattern.md): Karpathy's idea file for agent-maintained knowledge bases.
