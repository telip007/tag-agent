# Reserved multi-file transfer set

Three authored synthetic repositories extend confirmation beyond isolated
functions. Each requires coordinated changes in two source modules, preserves
existing tests/unrelated files, and is checked externally for API/CLI behavior.

- Inventory CSV importer: strict validation, additive upserts, transaction
  rollback after a late SQLite failure, and CLI success/error behavior.
- Framed client: arbitrary byte chunks, multiple/empty frames, partial state,
  oversize failure/reset, finish validation and strict UTF-8 integration.
- Tree report: recursive/hidden files, byte/record accounting, symlink/binary
  exclusion, stable ordering and JSON CLI/error behavior.

All supplied implementations failed and all reference repairs passed the
external oracles before this reserve was frozen. `oracle-validation.json`,
`frozen.json` and source snapshots preserve those checks. No subject requests
have used these tasks. Prompt/template selection and hashes must be frozen
before execution; feedback may assess the recommendation but cannot tune it
and still be called held out. Three repetitions per model are planned for
baseline and the recommendation on the two development aliases and Gemini.
These are author-created synthetic tests, not independently curated real-world
benchmark evidence.
