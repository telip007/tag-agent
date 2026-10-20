---
title: Session navigation TUI
summary: Keyboard-first session search and conversation previews, with deliberate workspace scope and safe draft-preserving transitions.
updated: 2026-10-20
---

# Session navigation TUI

The user explicitly raised the quality bar for navigating and selecting
sessions while the [persistent-session implementation](persistent-sessions-plan.md)
was in progress. A functional ID list is insufficient. This brief refines the
existing scope without adding autonomous lookup or background agents.

## Context and direction

The person is coding in a terminal, switching tasks and trying to recognize
where an earlier conversation left off. They should find it from its words,
check a preview and act without memorizing identifiers or losing a draft.
Success means immediate keyboard access, stable selection while filtering,
useful previews, and unambiguous workspace ownership and action labels.

Domain: workspaces, conversations, turns, interrupted tools, accepted messages,
drafts and source excerpts. The signature is a conversation preview paired
with the next safe action: continue here, inspect elsewhere or reference it.

The color world is the existing terminal canvas, muted gray rules, gold focus,
teal code, green additions and red failures. Reuse `Theme`, `SearchLine`,
`modal`, `KeyHints` and Stipple primitives. The terminal owns its font and
background; hierarchy comes from bold titles, dim metadata, cell spacing and
one gold selected row. No separate visual theme or color-only status.

Avoid a UUID-led table, a bare dropdown with no preview, and silent switching
from a search result. Titles and recognizable excerpts lead; details explain
where a session belongs; selection and activation are separate actions.

## Interaction contract

- Ctrl-O and `/sessions` open the session navigator while preserving input.
- Search receives typing immediately. Arrow keys and Ctrl-K/Ctrl-J move;
  page keys move by a visible page. Enter activates, Escape returns focus
  and the unchanged draft. Mouse single-click selects; double-click activates.
- Scope starts at the exact current workspace. A visible toggle exposes all
  workspaces. Scope and result count remain visible while typing.
- Recent sessions are stable and paginated; search reaches older sessions,
  rather than filtering only the first loaded page. Highlight remains on the
  same UUID when possible. Async results never replace newer queries/previews.
- On a wide terminal, show a list and conversation preview together. On a
  narrow terminal, keep a compact list and a selected-conversation excerpt
  below it. Long titles, paths and Unicode never overlap hints or borders.
- Each row leads with title, then a short human conversation excerpt. Secondary
  detail shows workspace and relative activity; the current session is marked
  in text as well as color. The preview identifies model and workspace.
- The primary action says continue for the current executable workspace and
  inspect for another workspace. Ownership conflicts open a clearly labeled
  read-only snapshot and never take over the other process.
- New session and rename are discoverable in navigator hints/command palette.
  Ctrl-N creates, Ctrl-R renames, and Ctrl-L selects a reference.
  Renaming is local, inline and cancelable. Creating or switching is refused
  while a turn is active; browsing/previewing remains read-only.
- `/reference` without an ID opens this navigator in reference mode. Choosing
  a source leads to a bounded excerpt preview and explicit attachment, rather
  than switching sessions. Direct ID commands remain optional shortcuts.
- Loading, no saved sessions, no matches, query failure, busy execution,
  unavailable model and read-only inspection each have specific useful copy.
  Recovery keeps the current conversation and input intact.

## Component intent checkpoints

Navigator: the selected title and excerpt are focal. Use existing muted modal
surface with one gold focus edge; two cells horizontal padding and one blank
line between controls, content and hints. Monospace titles use bold weight;
metadata stays dim. Height is stable during filtering, bounded by the terminal.

Preview: readable conversation text leads; model/path/ID are secondary. It
shares the modal surface and uses a quiet divider at wide widths. Keep a
bounded number of wrapped lines and explicitly show truncation. Preview is
historical data, not an active conversation or a permission grant.

Reference preview: clearly name the source and excerpt count/size. The primary
action is attach to the current draft. Escape preserves the current draft
without attachment. The attached source remains visible before sending.

Current-session header: show a compact recognizable title and read-only/paused
status when relevant. Session switching resets transient browse selection,
restores the target draft, and preserves the previous draft durably.

## Verification

Test real picker state transitions, keyboard activation, selection retention,
stale-query cancellation and no unintended model/tool invocation. Render wide,
standard and narrow terminal sizes, with long titles, Unicode, loading, empty,
error and read-only states. Inspect actual rendered screens for clipping,
hierarchy and usable hints. Measure search/preview latency on the specified
large session fixtures before calling the navigator finished.
