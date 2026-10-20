# Native development 01 — interrupted

The production Tag loop, adapters and tools completed 18 fixture trajectories
successfully. The run terminated after 20 of 72 scheduled jobs: one DeepSeek
request timed out and another job reached the 180-second process deadline.
The remaining 52 jobs did not execute. Failed rows remain in the dataset.
This incomplete and unbalanced matrix cannot rank prompt policies.

All 18 normally completed trajectories passed their external functional or
behavioral check and preserved the protected fixture files. The two interrupted
jobs had not completed their implementations. The recorded token usage is a
lower bound; requests without a completed response have unknown usage/cost.

Investigation reconstructed the failing line-buffer conversation with an earlier
assistant tool call that contained no reasoning text. The request without a
`reasoning_content` field received HTTP 400 explicitly requiring that field;
adding an empty field received HTTP 200 with native tool calls. These diagnostic
requests used reconstructed messages and were not byte-identical replays of the
native timed-out request. They establish a protocol-compatibility defect, not
the cause of both timeouts. Neither timeout proves that a prompt is worse.

The production Chat Completions encoder only sent nonempty replay reasoning,
so it could omit the field on these turns even with interleaving configured.
A regression test and a narrowly scoped repair are being validated. Subsequent
comparisons must use a new manifest and the repaired harness; do not silently
pool their results with this version.

After capture, a privacy-only pass redacted both macOS temporary-path spellings
in result data. Job identities, outcomes, code, counts and grades were preserved.
`analysis.json` validates row/detail equality and the archived source hashes.
`source/` contains the 69 source files pinned for this run. The actual system
prompt policy in production was not changed.
