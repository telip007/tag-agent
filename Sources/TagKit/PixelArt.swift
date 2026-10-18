import Stipple

/// A small picture drawn with half blocks. Each character cell shows two
/// pixels stacked: `▀` takes the top pixel's colour as foreground and the
/// bottom one's as background, so each cell can hold two colours. A cell is
/// about twice as tall as it is wide, so the pixels come out roughly square.
struct PixelArt {
    /// One string per pixel row, one character per pixel; `.` is transparent.
    let rows: [String]
    /// The colour of each pixel character.
    let palette: [Character: Color]

    /// The picture as lines of text, two pixel rows per line.
    @MainActor var lines: [Text] {
        let width = rows.map(\.count).max() ?? 0
        let pixels = rows.map { Array($0) + Array(repeating: ".", count: width - $0.count) }
        return stride(from: 0, to: pixels.count, by: 2).map { top in
            let upper = pixels[top]
            let lower = top + 1 < pixels.count ? pixels[top + 1] : Array(repeating: ".", count: width)
            return zip(upper, lower).reduce(Text("")) { line, pair in
                line + cell(top: palette[pair.0], bottom: palette[pair.1])
            }
        }
    }

    @MainActor private func cell(top: Color?, bottom: Color?) -> Text {
        switch (top, bottom) {
        case (nil, nil):
            Text(" ")
        case (let top?, nil):
            Text("▀").foregroundStyle(top)
        case (nil, let bottom?):
            Text("▄").foregroundStyle(bottom)
        case (let top?, let bottom?) where top == bottom:
            Text("█").foregroundStyle(top)
        case (let top?, let bottom?):
            Text("▀").foregroundStyle(top).background(bottom)
        }
    }
}

/// Tag's mascot: a small creature in Ottoman dress, drawn as ``PixelArt``.
enum Mascot {
    /// The colours, from Ottoman art: İznik turquoise, manuscript gold,
    /// cobalt and red from the tiles, and turban cloth.
    static let palette: [Character: Color] = [
        "T": Theme.tile,
        "K": Color(red: 24, green: 26, blue: 34),
        "W": Color(red: 240, green: 234, blue: 214),
        "w": Color(red: 196, green: 188, blue: 166),
        "G": Theme.accent,
        "B": Color(red: 31, green: 78, blue: 156),
        "R": Color(red: 192, green: 57, blue: 43),
    ]

    /// Wearing a wrapped turban with a gold jewel and a cobalt plume, the
    /// sorguç of the sultans' turbans.
    static let turban = PixelArt(
        rows: [
            "......GB......",
            "....WWGGWW....",
            "..wwwwwwwwww..",
            "..WWWWWWWWWW..",
            "...wwwwwwww...",
            "...TTTTTTTT...",
            "...TKTTTTKT...",
            ".TTTTTTTTTTTT.",
            "...TTTTTTTT...",
            "...T.T..T.T...",
        ],
        palette: palette,
    )

    /// Wearing a red fez with a dark tassel.
    static let fez = PixelArt(
        rows: [
            ".....KK.......",
            ".....RRRRK....",
            "....RRRRRRK...",
            "....RRRRRRK...",
            "...TTTTTTTT...",
            "...TKTTTTKT...",
            ".TTTTTTTTTTTT.",
            "...TTTTTTTT...",
            "...T.T..T.T...",
        ],
        palette: palette,
    )
}
