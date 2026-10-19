# AGENTS.md

Instructions for coding agents (and humans) working on Tag Agent.

## What this is

Tag Agent is a coding-agent harness CLI written in Swift. It started as a
learning project with a hand-written core; agents now build it together with
the maintainer. See `wiki/decisions/0006-agents-build-the-harness.md`.

- `Sources/Tag/`: the command-line entry point (argument parsing, terminal I/O).
- `Sources/TagKit/`: the agent itself (loop, model access, tools).
- `Packages/OpenRouter/`: the swift-openrouter SDK, a git submodule with its
  own `AGENTS.md`, rules and wiki. Work inside it follows *its* instructions.

## Before you start

1. Read `wiki/index.md` and the relevant pages.
2. SDK questions: `Packages/OpenRouter/README.md` and
   `Packages/OpenRouter/wiki/index.md`. OpenRouter API behaviour:
   https://openrouter.ai/docs/llms.txt (append `.md` to any docs URL).
3. Dependency APIs: read the exact resolved versions in `.build/checkouts/`.
   Apple/Swift docs: the DocC JSON behind a page, or a converter such as sosumi.ai.

## Commands

| Command | What |
| --- | --- |
| `make bootstrap` | install SwiftLint and ripgrep, enable git hooks, fetch the SDK submodule |
| `make fix` | auto-format |
| `make check` | wiki lint + swift-format + SwiftLint + build (warnings are errors) + tests + coverage |
| `make sdk-check` / `make check-all` | the SDK's own checks / both |

## Rules

- `make check` must pass before work is called done.
- Never weaken a check (no lint disables, no lowering coverage, no
  `@preconcurrency`/`nonisolated(unsafe)`/`try!`). If a rule seems wrong, ask
  and record a decision in `wiki/decisions/`.
- SDK changes are committed and pushed in the submodule first, then the
  submodule pointer is committed here.
- Commit messages and PR titles follow [Conventional Commits](https://www.conventionalcommits.org/)
  (`feat(tools): …`, `fix: …`, `feat!: …` for breaking changes; checked by
  the `commit-msg` hook and CI), the same format as the SDK.
- This repository is public: no personal data, local paths or
  machine details in code, docs, wiki or commit messages.

## Wiki duties

After any change to code, configuration, tooling or decisions:

1. Update the affected pages in `wiki/` and bump their `updated:` date.
2. Add a decision record for new decisions, and gotchas to the relevant page.
3. Append `## [YYYY-MM-DD] update | <what>` to `wiki/log.md`.
4. `make wiki-lint`.

Design work (brainstorms, specs, mockups, plans, also from skills that
default to `docs/superpowers/`) goes in `wiki/designs/`.

Record what was learned while building (concepts, mistakes, design choices)
in the wiki too, whoever wrote the code.

Conventions: `wiki/SCHEMA.md`. Workflow: `.claude/skills/wiki/SKILL.md`.
