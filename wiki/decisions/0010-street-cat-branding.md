---
title: Street cat branding
summary: Partly superseded by 0011. Tag Agent keeps its name and gets a tabby street cat in a fez as a quiet mascot, used in the README banner and logo, not as UI decoration.
updated: 2026-10-19
---

Superseded by [0011](0011-pixel-art-mascot.md) on how the mascot is drawn
and where it appears; the name and the cat in a fez stay.

# 0010 Street cat branding

## Context

The README banner was an abstract ornament; the project had no face. The
maintainer wanted a light rebrand: a recognisable logo and a little character
in the README, without cats all over the terminal UI.

## Decision

1. **Keep the name.** Tag Agent, `Tag` and `TagKit` stay; renaming would touch
   the package, the module, the repository and every page for no gain.
2. **Mascot: a tabby street cat in a fez**, teal eyes, gold and red accents on
   the existing navy, teal and gold palette.
3. **Where it appears:** the README banner (`.github/assets/banner.png`), the
   logo (`.github/assets/logo.png`, usable as avatar or social preview) and a
   short README section. Not in the TUI beyond what is already there: no cats
   in transcripts, status bars or prompts.
4. **Images come from Codex**, as before: a text-free background and a logo
   mark, with exact text composed by `compose-banner.swift`, which now also
   places the logo beside the title. No hand-drawn vector stand-ins.
5. **Wording stays neutral:** public pages describe the mascot as a street
   cat in a fez and say nothing more about its background.

## Consequences

- Regenerate the banner with
  `swift .github/assets/compose-banner.swift .github/assets/banner-background.png .github/assets/banner.png`;
  `logo.png` must sit next to the background.
- Prompts for new images: no text, letters or symbols in the picture, and the
  left of the banner stays dark and calm for the terminal window.
