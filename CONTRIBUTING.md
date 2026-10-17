# Contributing

Thanks for helping! Bug reports, new tools, docs fixes and ideas are all
welcome.

## Setup

```sh
git clone --recurse-submodules https://github.com/telip007/tag-agent.git
cd tag-agent
make bootstrap   # installs SwiftLint and ripgrep via Homebrew, enables .githooks, fetches the SDK
make check       # what CI runs: wiki lint, format, lint, build, tests, coverage
```

You need Swift 6.2+ (Xcode 26) and macOS 15+.

`make bootstrap` sets `git config core.hooksPath .githooks` for this repository
only. The pre-commit hook runs the linters and wiki checks; the pre-push hook
runs `make check`. If you use Claude Code, the committed hooks in
`.claude/settings.json` do the same automatically once you trust the folder,
and also lint each edited file. See `wiki/concepts/agent-workflow.md`.

## Making changes

- Read `AGENTS.md`. It applies to humans too, and is short.
- Model access goes through [swift-openrouter](https://github.com/telip007/swift-openrouter),
  a submodule in `Packages/OpenRouter`. Changes there are PRs to that
  repository first; see `wiki/concepts/openrouter-sdk.md`.
- Add tests for behaviour changes. Coverage of `Sources/` must stay ≥ 80 %.
- Update the wiki (`wiki/`) when you change behaviour or make a decision, and
  append a line to `wiki/log.md`. Reviewers will ask for it.
- Never weaken a check (lint disables, lower coverage, `try!`, …). If a rule
  seems wrong, open an issue and we record a decision in `wiki/decisions/`.

- Write commit messages and PR titles as
  [Conventional Commits](https://www.conventionalcommits.org/):
  `feat(tools): add a code_search tool`, `fix: …`, `docs: …`, `test: …`,
  `ci: …`, `refactor: …`, `chore: …`; `feat!: …` for breaking changes. The
  `commit-msg` hook and CI check it. PRs are squash-merged, so the **PR
  title** becomes the commit on `main`.

## Pull requests

- Keep PRs focused, with a Conventional Commits title and a description of
  what and why.
- CI must be green.
- By contributing you agree that your contributions are licensed under the
  Apache License 2.0.

## Reporting bugs

Please include the Swift and macOS versions, the model, what you asked the
agent, and what it printed (redact keys and anything private).
