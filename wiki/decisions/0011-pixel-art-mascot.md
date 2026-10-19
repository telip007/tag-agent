---
title: Pixel-art mascot
summary: The street cat in a fez becomes a pixel-art sprite in TagKit; it greets an empty conversation in the TUI, and the logo and banner are drawn from it and a real rendered screen, replacing the generated illustrations.
updated: 2026-10-19
---

# 0011 Pixel-art mascot

Supersedes [0010](0010-street-cat-branding.md) on how the mascot is drawn
and where it appears; the name and the cat in a fez stay.

## Context

The generated logo and banner from 0010 didn't hold up: a generic vector cat,
a painted scene that matched nothing else in the project, and a banner whose
sample session still showed the old line-by-line REPL. The maintainer wanted
a pixel-art mascot like Claude Code's and Codex's, also in the TUI.

## Decision

1. **The cat is a sprite in code**: `Mascot.sprite` in
   [Mascot.swift](../../Sources/TagKit/Mascot.swift), 18 × 17 pixels, one
   character per pixel, with a `palette`. No outlines: flat shapes read on a
   dark terminal, where a dark outline vanishes. Orange tabby, red fez with a
   band and a gold tassel (the UI's accent), teal eyes, cream muzzle and chest.
2. **In the TUI it greets an empty conversation** (`Welcome`, drawn with half
   blocks, 18 × 9 cells) at start and after `/clear`, and nowhere else: no
   cats in transcripts, the panel, the status or the prompt. Short terminals
   leave it out.
3. **The README images are drawn, not generated**:
   `.github/assets/render-assets.swift` reads the sprite and palette from
   `Mascot.swift` and writes `logo.png` and `banner.png`. The banner's
   terminal is a real Stipple render of a scripted session
   (`banner-screen.ansi`, written by `BannerScreenTests` when
   `TAG_BANNER_SCREEN` is set), so it shows the UI as it is.
4. **Wording stays neutral**, as in 0010: public pages call it a tabby street
   cat in a fez and say nothing more about it.

## Consequences

- Changing the cat is editing the sprite; the TUI, logo and banner follow.
  Regenerate the images with
  `TAG_BANNER_SCREEN=$PWD/.github/assets/banner-screen.ansi swift test --filter BannerScreen`
  then `swift .github/assets/render-assets.swift`, also after UI changes the
  banner should show.
- The script parses `Mascot.swift` with two regular expressions: keep the
  sprite one string literal per line and the palette as `"X": 0xRRGGBB,`.
- `banner-background.png` and `compose-banner.swift` are gone.
