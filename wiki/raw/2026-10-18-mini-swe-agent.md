# mini-swe-agent — capture

- URL: https://github.com/swe-agent/mini-swe-agent (v2, `main` branch)
- Files read: `src/minisweagent/agents/default.py`, `environments/local.py`,
  `models/litellm_model.py`, `models/utils/actions_toolcall.py`,
  `models/utils/cache_control.py`, `models/utils/retry.py`,
  `agents/interactive.py`, `config/mini.yaml`,
  `config/benchmarks/swebench.yaml`, `docs/faq.md`
- Captured: 2026-10-18
- MIT licence. This file holds excerpts and notes only.

## Excerpts

README:

> What if our agent was 100x simpler, and still worked nearly as well?

> Does not have any tools other than bash — it doesn't even need to use the
> tool-calling interface of the LMs.

> Has a completely linear history — every step of the agent just appends to
> the messages and that's it.

> Executes actions with `subprocess.run` — every action is completely
> independent (as opposed to keeping a stateful shell session running).

System message in `swebench.yaml` (the rest of the prompt is the first user
message):

> You are a helpful assistant that can interact with a computer shell to
> solve programming tasks.

Workflow from the first user message:

> 1. Analyze the codebase by finding and reading relevant files
> 2. Create a script to reproduce the issue
> 3. Edit the source code to resolve the issue
> 4. Verify your fix works by running your script again
> 5. Test edge cases to ensure your fix is robust

> Directory or environment variable changes are not persistent. Every action
> is executed in a new subshell.

`mini.yaml`, OS-specific rule:

> You are on MacOS. For all the below examples, you need to use `sed -i ''`
> instead of `sed -i`.

Observation template: output under 10,000 characters is shown whole; longer
output becomes `<output_head>` (first 5,000), `<elided_chars>`,
`<output_tail>` (last 5,000) plus:

> Please try a different command that produces less output.

FAQ, why no shell session:

> It's not obvious when a command has terminated. […] Particularly bad
> commands from the LM can kill the shell session. Then what?

## Notes

- `DefaultAgent` is about 100 lines: query, append, execute, append; stops
  on a message with role `exit`. Saves the trajectory in a `finally` after
  every step.
- `LocalEnvironment` runs `Popen(shell=True)` in a new session and kills the
  process group on timeout (30 s default, 60 s for SWE-bench).
- Retries: tenacity, 10 attempts, exponential wait 4–60 s; aborts on auth,
  not-found, unsupported params, context window exceeded.
- Format errors are fed back as a user message; `finish_reason == "length"`
  gets its own hint; three in a row end the run.
- Anthropic caching: `set_cache_control` marks only the last message
  `ephemeral`.
- Limits: `step_limit`, `cost_limit` (default $3), `wall_time_limit_seconds`.
- Interactive agent: modes `human` / `confirm` / `yolo`, regex whitelist,
  Ctrl-C asks for a comment that becomes a user message, confirm before
  exiting.
- Environment variables set for tools: `PAGER=cat`, `MANPAGER=cat`,
  `LESS=-R`, `PIP_PROGRESS_BAR=off`, `TQDM_DISABLE=1`.
