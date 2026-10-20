import Stipple

/// Tag's mascot, a tabby street cat in a fez, as pixel art. The sprite is the
/// one source for the cat: the welcome screen draws it with half blocks, and
/// `.github/assets/render-assets.swift` reads it from this file to draw the
/// logo and the banner.
@MainActor
enum Mascot {
    /// One character per pixel; `.` is transparent.
    static let sprite = [
        "......RRRGRR......",
        "..O...RRRRGR...O..",
        "..OO.RRRRRRGR.OO..",
        "..OIORRRRRRGGOIO..",
        ".OIIODDDDDDDDOIIO.",
        ".OOOOOOSOOSOOOOOO.",
        ".OOOOOOOSSOOOOOOO.",
        ".OOEkOOOOOOOOkEOO.",
        ".OOEkOOOOOOOOkEOO.",
        "WSOOOOCCNNCCOOOOSW",
        ".OOOOCCCkkCCCOOOO.",
        "WSOOOCCkCCkCCOOOSW",
        "..OOOOOCCCCOOOOO..",
        "...OOSOCCCCOSOO.O.",
        "...OOSOCCCCOSOO.S.",
        "...OOOOCCCCOOOOOO.",
        "...OCCOCCCCOCCOO..",
    ]

    /// The colours, as `0xRRGGBB`.
    static let palette: [Character: UInt32] = [
        "R": 0xD8403F,  // fez
        "D": 0x9E2632,  // fez band
        "G": 0xE3B341,  // tassel, the UI's gold accent
        "O": 0xF3A447,  // fur
        "S": 0xC2662A,  // stripes
        "C": 0xFCE7C4,  // muzzle, chest and paws
        "I": 0xF2B0A6,  // inside the ears
        "E": 0x34D1C0,  // eyes
        "k": 0x1B1A2E,  // pupils and mouth
        "N": 0xEF8A9B,  // nose
        "W": 0xFFFFFF,  // whiskers
    ]

    /// The sprite as lines of half blocks, two pixels to a cell: the upper
    /// one in the foreground of `▀`, the lower one behind it.
    static var lines: [Text] {
        stride(from: 0, to: sprite.count, by: 2).map { row in
            let upper = Array(sprite[row])
            let lower = row + 1 < sprite.count ? Array(sprite[row + 1]) : []
            return upper.indices.reduce(Text("")) { line, column in
                line + cell(upper: color(upper[column]), lower: column < lower.count ? color(lower[column]) : nil)
            }
        }
    }

    private static func cell(upper: Color?, lower: Color?) -> Text {
        switch (upper, lower) {
        case (nil, nil): Text(" ")
        case (let upper?, nil): Text("▀").foregroundStyle(upper)
        case (nil, let lower?): Text("▄").foregroundStyle(lower)
        case (let upper?, let lower?): Text("▀").foregroundStyle(upper).background(lower)
        }
    }

    private static func color(_ pixel: Character) -> Color? {
        palette[pixel].map { Color(red: UInt8($0 >> 16 & 0xFF), green: UInt8($0 >> 8 & 0xFF), blue: UInt8($0 & 0xFF)) }
    }
}

/// What the conversation pane shows before the first message: the cat, the
/// name and where to start. Short panes leave the cat out.
struct Welcome: View {
    /// Terminals shorter than this show the welcome without the cat.
    static let catMinimumHeight = 20

    @Environment(\.terminalSize) private var terminalSize

    var body: some View {
        VStack(alignment: .center) {
            if terminalSize.height >= Self.catMinimumHeight {
                ForEach(Array(Mascot.lines.enumerated()), id: \.offset) { _, line in
                    line
                }
                Text(" ")
            }
            Text("Tag Agent").bold().foregroundStyle(Theme.accent)
            Text("ask anything below · ^p commands").dim()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
