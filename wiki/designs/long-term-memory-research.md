---
title: Efficient long-term memory and selective dreaming
summary: Research proposal for native evidence-backed memory, bounded hybrid retrieval, an inspectable wiki and optional incremental consolidation.
updated: 2026-10-20
---

# Efficient long-term memory and selective dreaming

Status: research recommendation, not an approved implementation decision.
Research date: 2026-10-20. Selected primary literature, not an exhaustive
review; no paper benchmarks or proposed memory components were reproduced.
The goal is useful cross-session experience with very little additional
LLM work, rather than the highest score regardless of cost.

## What exists

Inspected local baseline: `a560e90`, native context integration on main.
[SessionKit](../../Sources/SessionKit/SessionAppend.swift) already saves
semantic events transactionally, with derived readable entry search.
[OutputIndex](../../Sources/SessionKit/OutputIndex.swift) indexes retained
output chunks with optional FTS5; [OutputSearch](../../Sources/SessionKit/OutputSearch.swift)
combines literal matches and BM25. This is not yet a ranked cross-session
memory index. [History tools](../../Sources/TagKit/ContextHistory.swift)
are confined to the active session. [ContextRequestProjection](../../Sources/TagKit/ContextRequestProjection.swift)
supports explicit reversible compaction, and
[prompt caching](../concepts/prompt-caching.md) preserves stable prefixes.

[ADR 0015](../decisions/0015-persistent-sessions.md) and
[ADR 0016](../decisions/0016-native-context.md) deliberately defer automatic
retrieval and promotion. Extend their canonical store; do not introduce a
second session history, hosted memory service or always-running daemon.

## Research that changes the recommendation

Results below are authors' measurements in their own configurations.
Metrics, readers, graders and budgets differ: this table is not a leaderboard.

| Primary source and inspected material | Finding and implication |
| --- | --- |
| [RecMem, v1](https://arxiv.org/html/2605.16045v1), §§3–4, §6 | Keeps raw interactions retrievable and consolidates recurring semantic clusters. LoCoMo/GPT-4.1-mini construction tokens fall from 1,520.8K for Mem0 to 193.2K, an 87.3% reduction. Thresholds are heuristic; rare important events can be missed. Best fit for selective construction, with a separate path for explicit one-off constraints. |
| [LightMem, v3](https://arxiv.org/html/2510.18866v3), §§3–5 | Topic batching and offline updates reduce online maintenance. The paper distinguishes total efficiency (up to 20.92× token efficiency on LoCoMo) from much larger online-only savings. Summarization still invokes an LLM. Borrow batching and deferred maintenance, not a claim that sleep is free. |
| [SAGE, v2](https://arxiv.org/html/2605.30711v2), §3, §4 Table 3 and Appendix H | Embedding-space novelty routes clear additions and duplicates without LLM routing. Shared extraction still costs 1,696 calls; counting it, write calls fall 29–42% on seven backbones. GPT-4o-mini average judge score is 52.2 versus Mem0's 53.5. Borrow cheap gating; similarity alone cannot establish semantic equivalence or truth. |
| [SimpleMem, v3](https://arxiv.org/html/2601.02553v3), §2 and Tables 1–2 | Combines semantic, lexical and metadata views with LLM extraction, synthesis and query planning. Reports up to 30× fewer inference tokens than full context. Good precedent for hybrid access and dense records; its complete pipeline does not meet a zero-generative-call default. |
| [Hindsight, v1](https://arxiv.org/html/2512.12818v1), abstract and architecture | Separates facts, experiences, entity summaries and beliefs. Reports 91.4% LongMemEval with a scaled reader; this is not a latency- or model-matched comparison with Tag. Adopt evidence/inference distinctions without immediately adopting the whole reflection architecture. |
| [Sleep-time Compute](https://arxiv.org/abs/2504.13171), abstract | Offline reasoning amortizes over related questions; the reported 2.5× average cost reduction concerns Multi-Query GSM-Symbolic. Benefit depends on predictable reuse, not merely idle scheduling. |
| [LongMemEval](https://arxiv.org/abs/2410.10813), abstract | Evaluates extraction, multi-session/temporal reasoning, updates and abstention. Include these capabilities in tests, not just similarity recall. |
| [LongMemEval-V2, v1](https://arxiv.org/html/2605.12493v1), §5 Table 2 | Specialized web histories test operational experience. AgentRunbook-C reaches 74.9%/70.1% on small/medium tiers but needs 108.3/139.9 seconds for context gathering. The best quality path is not necessarily suitable for automatic retrieval before each turn. Work in progress, not a coding-agent outcome benchmark. |
| [MemoryArena, v2](https://arxiv.org/abs/2602.16313v2), abstract | Strong conversational recall can coexist with poor multi-session action performance. Tag must evaluate executable outcomes and repeated mistakes. |
| [The Epistemics of Agent Memory](https://arxiv.org/abs/2609.33013), abstract | Recent exploratory preprint reports that its consolidation quality score did not predict real transfer accuracy. Useful caution against optimizing a proxy; not treated as an established winning method. |

## Recommended architecture

These are engineering proposals inferred from the evidence, not experimentally
established optimal parameters.

```text
session events and retained outputs (canonical evidence)
                 |
     incremental native memory projection
       /                            \
exact/lexical index          optional local embeddings
       \                            /
     scope and validity filters, rank fusion
                 |
       small cited memory packet -> ordinary agent
                 |
       useful new knowledge / repeated experiences
                 |
      changed-cluster queue -> optional consolidation
                 |
      versioned claims, links, inspectable wiki pages
```

### Capture automatically; distinguish capture from interpretation

After committed events, incrementally index readable conversation episodes,
explicit user statements and structured tool metadata. Resume by a separate
canonical-sequence cursor per session: sequence numbers are session-local.
Schedule bounded, workspace-scoped catch-up fairly across sessions rather
than rereading every session or using a global sequence cursor. Index references to large outputs,
not copies of every successful build log in the semantic memory collection.
Bound ingestion, backlog, disk and indexing work; archive quotas remain real.

No LLM is needed to preserve exact user words, source coordinates, timestamps,
exit codes or an explicitly selected memory. That does not mean a rule can
reliably infer every preference, correction or reusable lesson. A failed test
and a later passing test are observations; their causal connection is a
candidate until supported. Explicit important one-off statements bypass the
recurrence gate as attributed statements, without inventing a normalized fact.

Suggested record fields: stable ID, workspace identity, kind, text, source
session/sequence or output/range/hash, recorded time, valid time when known,
authority class, evidence status, revision, supersedes/conflicts-with links,
expiry and deletion state. Record assertion time separately from event time.
User statements, tool observations and assistant hypotheses remain distinct.
User messages can themselves contain pasted documents or hostile quotations;
user authorship of the envelope does not make every contained sentence a
directive. Preserve source attribution, and grant directive authority only
through an explicit memory operation or otherwise verified user instruction.
Repeated assistant paraphrases are not independent confirmation.

### Retrieve locally and admit very little

Use exact identifier/path matching, FTS5/BM25 and structured scope/time filters
as the dependency-light baseline. Add a local embedding lane to handle
paraphrases and English/German crossover; merge bounded candidate lists by
reciprocal rank fusion, then deduplicate and diversify. RRF scores are ranks,
not calibrated probabilities. Learn admission thresholds on held-out tasks;
return nothing when evidence is insufficient. Keep literal matching for code
punctuation and identifiers. SQLite's Porter stemmer is English-oriented;
evaluate a separate general Unicode/code-friendly index for memory rather
than assuming the existing output tokenizer suits all memory.

Start without graph traversal, LLM query expansion or generative reranking.
Simple entity/topic/supersession links provide useful structure without a
graph server. Search only the current workspace plus explicitly shared
personal preferences; do not make all historical sessions globally visible.
If richer evidence is needed, expose bounded memory search and exact-read
tools rather than launching a separate retrieval agent automatically.

Embedding selection is a measured implementation choice. A candidate as of
the research date is [EmbeddingGemma 2](https://ai.google.dev/gemma/docs/embeddinggemma/model_card_2?hl=en):
the official card describes a separately loadable 270M text component,
multilingual/code retrieval and 256-dimensional truncation. Validate native
runtime support, format/license, cold start, working set and code recall
before choosing it; no Swift packaging or hardware benchmark was performed.
Use a swappable encoder; local embedding inference still consumes compute.
Cache by content hash plus encoder version. A flat vector scan is a small-store
baseline; switch to ANN only when measured scope size and latency warrant it.
Do not prefilter all dense candidates through lexical hits, which would lose
the paraphrase benefit.

Suggested experiment budgets: a first packet of about 512–768 tokens; at most
roughly 2,000 cumulative automatically injected memory tokens per session
epoch, including labels and references. Exact caps require the active model's
tokenizer; byte limits alone cannot guarantee them. Otherwise expose a byte
cap honestly and measure actual provider tokens separately. Packets may be
empty; the cap is a ceiling, not a target. Budget tool schemas and subsequent
explicit recall separately and report them in the total.

Do not rewrite the system prompt or historical memory packet on each model
iteration. Freeze each admitted packet as a cited session attachment and
deduplicate against already admitted IDs. Only consider new automatic
admission at user-turn boundaries and stop at the session budget. Additional
queries are explicit tool use. An explicit compaction starts a new request
epoch; it does not erase provenance. This limits memory admission, not all
conversation growth: existing pinned user messages can still fill context.

### Use a wiki as a compiled view

[Karpathy's supplied pattern](https://gist.githubusercontent.com/karpathy/442a6bf555914893e9891c11519de94f/raw/ac46de1ad27f92b28ac95459c782c07f6b8c964a/llm-wiki.md)
separates immutable sources, a maintained linked wiki and its schema. Adopt
inspectability, accumulated synthesis, citations, links and a chronological
log. Avoid automatic multi-page semantic rewrites on each source and reading
the complete index into every prompt. The source is an idea file, not an
efficiency study. Bookkeeping can be native; prose synthesis costs inference.

Keep versioned claims and their provenance in the existing database as the
single write authority; render private Markdown pages for projects, entities,
decisions and procedures on demand or when changed. Index pages are primarily
for humans. Derived links, backlinks, indexes and logs need no generative model.
Only substantive synthesis requires one. A materialized-view design must not
overwrite human edits: support edits through a native transaction or explicit
revision-checked import, recording human corrections as authoritative memory
revisions before regenerating. Passive file watching is not initial scope.

Keep private automatic memory separate from public repository documentation.
The repository wiki and any external knowledge vault remain deliberately
curated destinations; this proposal does not enroll them in automatic sync.
Export/import is explicit and scoped, not a second independent history.

### Dream only over changed, valuable clusters

Default maintenance needs zero generative calls: catch up indexes, hash-dedupe,
refresh links, mark source changes, apply explicit expiry, compact derived
indexes and produce structural diagnostics. Semantic similarity flags possible
duplicates; it must not merge different claims or contradictory statements.
Changing files marks observations potentially stale, not automatically false.

Optional semantic dreaming processes only new or changed clusters when
recurrence, unresolved conflict or repeated retrieval failures justify it.
An initial experiment could trigger after three distinct episodes, with
explicit user constraints handled immediately. Thresholds are tunable, not
research constants. Prioritize expected reuse and information value; a timer
alone never creates work. When the application is closed, leave the queue
durable and catch up next time rather than requiring a daemon.

Use one bounded batch, a source snapshot, explicit input/output/call/time
limits and an optional user-configured daily token/cost allowance. Zero is
a fully supported allowance. Budget reasoning tokens and retries when exposed;
a hard monetary guarantee needs suitable provider accounting, not guesswork.
Never hold a database transaction across inference. Apply a validated claim
delta only if source and target revisions still match; checkpoint only after
commit. Yield to interactive writes, particularly with current DELETE
journaling and the single DatabaseQueue. Background processing is cancellable
and must not delay a user request waiting for the model or a long write lock.

Outputs are evidence-linked candidate rules or summaries. Dreaming cannot
invent new facts, turn web text into instructions, overwrite user decisions,
silently resolve ambiguous contradictions or execute learned commands.
Repetition can increase consolidation priority, never authority. Remove
superseded claims from normal current-state retrieval while retaining audit
history. Historical/as-of queries can deliberately inspect old revisions.

“Remember” and “forget” need native operations. Forgetting suppresses future
retrieval immediately and covers claims, vectors, rendered pages, job queues
and caches; canonical transcripts and backups have separate disclosed deletion
semantics. A tombstone prevents regeneration from old evidence until deliberate
re-enrollment. Secret filters reduce exposure but cannot guarantee perfect
detection; protected paths and explicit no-store scopes must apply before
memory indexing.

## Querying and indexing stress check

The follow-up question on indexing and token efficiency changes the emphasis:
the architecture is a candidate to benchmark, not a demonstrated optimum.
Avoid optimizing only the size of the final memory packet while paying for
large hidden query-planning, reranking or consolidation calls.

Additional primary checks:

- [LongMemEval v2, §§5.2–5.3](https://arxiv.org/html/2410.10813v2):
  conversation rounds can outperform whole-session values; replacing raw
  values entirely with facts/summaries loses information. Fact-augmented keys
  improve retrieval in its LLM-assisted setup. Small readers can degrade
  beyond 3K tokens while GPT-4o benefits beyond 20K. The proposed 2K automatic
  budget is therefore a conservative product default, not a universal optimum.
- [BM25 Wins at Scale, v3, abstract](https://arxiv.org/abs/2607.26497v3):
  a controlled RAG scaling study finds a size-dependent crossover, with BM25
  overtaking file-system exploration around 10M corpus tokens in its setup.
  Sequential file exploration costs 39× more query tokens at the smallest
  tier. This supports ranked discovery before agentic reading; it does not
  prove lexical-only memory is always best for Tag or bilingual paraphrases.
- [Chunking taxonomy/evaluation, abstract](https://arxiv.org/abs/2602.16974):
  best segmentation is task-dependent; simple structure-based methods beat
  LLM-guided alternatives for its in-corpus retrieval setting. Do not pay for
  semantic chunk creation on every message without a measured benefit.
- [Late Chunking, v3, abstract](https://arxiv.org/abs/2409.04701v3):
  pooling chunks after contextual embedding can retain surrounding meaning
  without a generative summary. It requires compatible token-level encoder
  access and more surrounding-text computation. Keep as a later experiment.
- [QMD README, search modes/models/query flow](https://github.com/tobi/qmd):
  lexical search is separate from its full hybrid query mode, which uses local
  generative query expansion and reranking. Local execution does not mean no
  model work. Its natural Markdown boundaries and SQLite design are useful
  precedents without requiring its complete runtime or inference pipeline.

Recommended concrete pipeline, still to be validated:

1. Build separate retrieval units for coherent conversation rounds, individual
   durable claims and wiki sections. Preserve parent links, original spans,
   thread/topic labels and neighboring ranges. Do not embed a whole session
   or strip all context into isolated sentences. Add known metadata to search
   keys using templates; semantic decontextualization remains optional LLM work.
2. Incrementally index only changed units. Hash text together with relevant
   heading/context and encoder version so changed parent context invalidates
   a previously cached vector. Deduplicate repeated output content while
   preserving distinct occurrences and source coordinates.
3. Resolve exact memory IDs directly. Otherwise build a query from the user
   turn and bounded current-task identifiers. Run bounded lexical and, when
   enabled, dense candidate retrieval independently; do not require lexical
   success for the semantic lane. Workspace visibility is a hard filter;
   inferred dates and recency are generally ranking features unless the user
   supplied an unambiguous time constraint. Cache results by query, scope,
   policy/encoder version and index revision, including invalidation on forget.
4. Retrieve more candidates locally than will enter the prompt, for example
   20 per lane as an experimental starting point. Fuse ranks, resolve current
   revisions, remove duplicates and select complementary evidence per token.
   Ranking must handle negative and superseding evidence, not just similarity.
   Try a small local cross-encoder only if ambiguous matches measurably cause
   mistakes; include model loading, execution and memory cost in its comparison.
5. Return short useful evidence, source IDs and exact expansion handles, not
   arbitrary matched lines or full documents. Resolve pronouns by including
   minimal parent/neighbor evidence; do not invent an interpretation. Reserve
   expansion for the ordinary agent when it needs it. Multi-session/temporal
   questions can legitimately spend more than the automatic default through
   explicit bounded reads. A directory of pointers alone is not useful memory
   if following it adds a model round trip for every basic fact.

The most informative retrieval metric is evidence coverage at a fixed token
budget, paired with actual task success and total cost. Recall@5 can look
excellent while five huge chunks exhaust context. Conversely, 200 tokens
that omit a crucial exception can increase subsequent tool calls and total
task cost. Measure both candidate recall and admitted-packet coverage so
indexing failures can be separated from ranking/admission failures.

## Whole-task cost and evaluation

Zero additional generative calls is feasible for capture, search and structural
maintenance. Useful retrieved text still consumes the answering model's input
tokens. Embeddings have local latency, RAM and energy cost, even without API
billing. Optional same-turn memory proposals save a round trip, not output
tokens or truth verification. A local generative model is not free compute.

Consolidation pays off only when expected future context/reasoning savings
exceed its generation, indexing and maintenance costs. Include cached and
uncached input separately; tokens saved are not automatically dollars saved.

Compare: (A) no automatic memory, (B) native lexical memory, (C) hybrid local
memory with zero generative maintenance, (D) C plus selective consolidation.
Keep reader model, tasks, retrieved-token cap and stopping conditions fixed.
Use temporally held-out histories, no future answers in ingestion or tuning,
and repeated runs for variable model outcomes. Tune thresholds on development
tasks only. Report paired uncertainty, not just a single aggregate percentage.

Measure source precision/recall under the packet budget, no-match abstention,
updated-fact accuracy, harmful false recall, cross-workspace isolation,
poisoning resistance, deletion/rebuild behavior, p50/p95 warm and cold latency,
memory/RAM/disk growth and total construction plus query plus answer tokens.
Test rare one-off constraints, bilingual paraphrases, exact errors, obsolete
decisions, evidence from interrupted tools and failed hypotheses. Evaluate
actual coding outcomes: passing fixes, repeated mistakes, tool calls and
end-to-end time. Suggested warm-retrieval targets are p95 under 50 ms for
lexical and under 150 ms for hybrid; these are acceptance experiments, not
measured performance or promises. Measure cold encoder load independently.

Ship the zero-generative-call baseline first; enable local semantic retrieval
if its measured recall gains justify footprint, and selective dreaming only
if it improves task outcomes or total cost at equal quality. No universal
best or global state-of-the-art winner is established by this survey.
