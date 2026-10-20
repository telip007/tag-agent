# Selection protocol

This protocol is recorded while the native development comparison is running,
before any reserved functional confirmation task is sent to a subject model.
It selects a practical coding-agent policy for the measured distribution. It
does not claim a universal optimum over all possible prompts or tasks.

1. Audit every failed trajectory. Keep the original outcome and grade. Correct
   clear behavioral-rubric errors in a separate, hashed adjudication record,
   applying the same criterion across policies. External code-test failures
   cannot be overridden by behavioral adjudications.
2. Complete native exploration of the eight declared general-policy candidates,
   including a minimal control and the 98-word `adaptive_compact` proposal, on the same development tasks.
   It combines concise rules with explicit evidence, trust and stopping rules;
   it has no model-generated confirmation feedback.
3. Compare promising finalists with baseline over at least three repetitions
   per development model/task. Reuse earlier samples only when model IDs,
   policy text, fixture definitions, inference controls and native execution
   semantics are compatible and the reuse is documented. Preserve unique run
   and repeat identities; never count a sample twice.
4. Retain candidates with no demonstrated functional/scope regression. Display
   whole-run success and failures separately from code correctness, including
   provider timeouts. Conditional success is not an operational success claim.
5. Among retained candidates, compare task-paired token usage, model calls and
   recorded-usage allowance-rate estimates. Normalize against baseline within
   each model and give the two development models equal weight. A Pareto
   tradeoff is reported explicitly; a shorter policy does not win by length.
   Missing usage stays unknown. Latency remains observational under shared
   provider infrastructure.
6. Freeze finalist text/hashes and the development-based choice before opening
   the reserved confirmation results. Compare baseline and finalists on those
   six functional tasks, with repeated runs and additional model-family
   coverage. A third native API format requires its own smoke test first.
7. Publish the exact recommended policy/template, raw evidence, uncertainty,
   limitations and reproduction commands. If a confirmation regression changes
   the choice, disclose it. Any tuning based on confirmation results consumes
   that split; a revised policy then requires new unseen confirmation tasks.

Task-cluster bootstrap intervals are exploratory and do not establish
equivalence from identical small-sample scores. One provider timeout does not
establish a policy regression; repeated operational failures still matter to
the recommendation. A conclusion may favor the existing baseline if new
policies do not justify replacement.


Before final template selection, compare the standard rendered scaffold with a
lean representation of the promising core policy: shorten identity and omit the
redundant prose tool list, while retaining the actual API tool definitions,
tool-use guidelines, environment and project instructions. This separate
structural ablation addresses the whole system prompt. It must run on development
tasks before freezing confirmation finalists. No new general-policy candidates
are planned beyond the declared eight.


## Development fixture ambiguity audit

During the remaining native family run, before selection or any confirmation
request, `config-precedence` exposed an unstated float requirement. Its task
explicitly rejects non-integer strings, booleans and negatives but never defines
the accepted treatment of numeric floats. The oracle rejects `2.5`, whereas
GLM/combined truncates it through `int()`. Preserve that failed external grade.
Exclude the entire task uniformly from primary development selection and show
all-task sensitivity; do not adjudicate a code-test pass or silently edit the
fixture. The other eleven unchanged development tasks remain selection data.
See `results/native-family-comparison-01/data-quality.json` for the exact task
and failed-trajectory hashes. Future development repeats use those eleven tasks.


## Repeated-run interpretation and multi-file transfer

All-attempt cost per reviewed success includes the recorded usage of failed
attempts; it is reported only when usage for every attempted inference is
complete. Conditional successful-pair ratios remain separate and cannot hide
budget failures. Joint exploratory intervals resample whole tasks shared by
all represented models, average repeat samples within model/task, and give
models equal weight. Zero-width quality intervals from uniformly successful
samples do not establish equivalence; selection and multiple-comparison
uncertainty remain. These definitions precede the repeated finalist results.

Three additional multi-file transfer tasks are reserved before final prompt
selection: transactional inventory import plus CLI, incremental framed-protocol
decoder plus UTF-8 client, and recursive text inventory plus JSON CLI. Their
original implementations fail external checks and all reference repairs pass.
The definitions and source hashes are frozen in `results/transfer-reserve-01/`.
No subject model has received them. After the development-based prompt/template
freeze, compare baseline and the selected recommendation with three repetitions
per model on both development aliases and Gemini. Keep these results separate
from the original six-task confirmation suite. No tuning on either reserved set
can retain its held-out status; any revised recommendation requires fresh
unseen confirmation. This adds a transfer check for multi-file behavior without
claiming to be an independent real-world SWE benchmark.


## Predeclared context-position stress check

After the complete recommendation freeze, use the reserved framed-client task
for a small secondary stress test on all three model aliases: unchanged baseline
and recommendation, one attempt with the task block at each of three positions
(beginning/middle/end) among the same two synthetic archive blocks. The 18
conditions and 125,952-character archive are fixed in `results/context-reserve-01/`.
All conditions have identical blocks and character counts; provider token usage
is observed. This exercises the remaining context-position hypothesis from the
research plan, without claiming to reproduce Lost in the Middle or count these
conditions as independent new tasks. The ordinary nine-task, three-repeat
confirmation/transfer comparison remains unchanged. No tuning on the stress
results preserves held-out status. No further prompt candidates or experimental
phases are planned beyond this frozen pipeline.
