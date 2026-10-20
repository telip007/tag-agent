# Reserved context-position stress test

This closes the remaining context-position hypothesis from the research plan.
The eventual frozen recommendation and unchanged baseline will each run the
reserved `framed-client` multi-file task on DeepSeek, GLM and Gemini with the
task block at the beginning, middle and end of the same two archive blocks.
One trajectory per model/arm/position yields 18 stress cases. The ordinary
three-repeat confirmation and transfer protocol stays unchanged.

The archive has 125,952 deterministic ASCII characters in 1,024 unrelated
synthetic catalogue records. All conditions contain identical task/archive
blocks and character counts; only ordering changes. Actual token counts are
provider-reported at execution, not inferred from characters. The archive is
data, contains no operational commands, and represents no real user material.

`frozen.json` binds the exact parts, task hash, models, conditions and renderer.
`treatment-validation.json` verifies block identity and records rendered hashes.
Three renderer tests passed, including unchanged default input and rejection
of malformed treatments. Controller integration is deferred until the current
frozen native repeat process is terminal. No subject calls use this reserve.

These are stress conditions for one already reserved task, not additional
independent tasks or a reproduction of Lost in the Middle. Task-level evidence
is still limited. The template is frozen before execution; results cannot tune
it while retaining held-out status. This is the last planned experiment beyond
the existing repeated comparison and nine-task confirmation/transfer pipeline.
