# Security

## Reporting a vulnerability

Please report vulnerabilities privately via
[GitHub Security Advisories](https://github.com/telip007/tag-agent/security/advisories/new)
rather than public issues. We aim to respond within a week.

## The agent runs commands on your machine

Tag Agent gives a language model tools that read and edit files and run shell
commands (`bash`) in the directory you start it in, with your user's
permissions and without asking first. Run it only in directories you're
willing to let it change, ideally under version control, and never on
untrusted input you haven't read.

## API keys

- Never include API keys in issues, PRs, logs or test fixtures. If you
  accidentally publish one, revoke it immediately at https://openrouter.ai/keys.
- Pass the key through the `OPENROUTER_API_KEY` environment variable. Don't
  commit it in an Xcode scheme: `.swiftpm/` is ignored for that reason.
