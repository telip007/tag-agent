// Draws the README images from the mascot sprite and a real Tag screen:
//
//   logo.png    the cat, for the README, avatars and previews
//   banner.png  the title, a Tag Agent session in a terminal window and the cat
//
// Run it from the repository root:
//
//   TAG_BANNER_SCREEN=$PWD/.github/assets/banner-screen.ansi swift test --filter BannerScreen
//   swift .github/assets/render-assets.swift
//
// The first line renders the workspace with Stipple into banner-screen.ansi
// (Tests/TagKitTests/BannerScreenTests.swift); run it again when the UI
// changes. The sprite and its colours are read from Sources/TagKit/Mascot.swift.

import AppKit

let assets = URL(filePath: ".github/assets")

/// `0xRRGGBB` as a colour.
func color(_ hex: UInt32, alpha: Double = 1) -> NSColor {
    NSColor(
        srgbRed: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
        blue: Double(hex & 0xFF) / 255, alpha: alpha
    )
}

// MARK: The mascot

guard let mascotSource = try? String(contentsOfFile: "Sources/TagKit/Mascot.swift", encoding: .utf8) else {
    FileHandle.standardError.write(Data("run from the repository root\n".utf8))
    exit(1)
}
let sprite = mascotSource.matches(of: #/^\s*"([.A-Za-z]+)",$/#.anchorsMatchLineEndings()).map { Array(String($0.1)) }
let palette = Dictionary(
    uniqueKeysWithValues: mascotSource.matches(of: #/"(.)": 0x([0-9A-F]{6}),/#).map {
        (Character(String($0.1)), UInt32($0.2, radix: 16) ?? 0)
    })

/// Draws the cat with its top-left corner at `origin` (top-left based), `scale` points to a pixel.
func drawCat(at origin: NSPoint, scale: Double, canvasHeight: Double) {
    for (row, pixels) in sprite.enumerated() {
        for (column, pixel) in pixels.enumerated() {
            guard let hex = palette[pixel] else { continue }
            color(hex).setFill()
            NSRect(
                x: origin.x + Double(column) * scale, y: canvasHeight - origin.y - Double(row + 1) * scale,
                width: scale, height: scale
            ).fill()
        }
    }
}

/// Runs `draw` on a fresh bitmap and writes it to `name` in the assets folder.
func render(_ name: String, width: Int, height: Int, draw: () -> Void) {
    guard
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )
    else { exit(1) }
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.shouldAntialias = true
    draw()
    NSGraphicsContext.current = nil
    guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
    try? png.write(to: assets.appending(path: name))
    print("wrote \(name)")
}

let navy: UInt32 = 0x0F1424
let width = Double(sprite.first?.count ?? 0)
let height = Double(sprite.count)

render("logo.png", width: 512, height: 512) {
    color(navy).setFill()
    NSRect(x: 0, y: 0, width: 512, height: 512).fill()
    let scale = 22.0
    drawCat(
        at: NSPoint(x: (512 - width * scale) / 2, y: (512 - height * scale) / 2 + 6), scale: scale,
        canvasHeight: 512)
}

// MARK: The screen

/// A terminal cell: a character and its SGR style.
struct Cell {
    var character: Character = " "
    var foreground: UInt32?
    var background: UInt32?
    var bold = false
    var dim = false
    var inverse = false
}

let basic: [Int: UInt32] = [
    30: 0x1B1E2B, 31: 0xF0626A, 32: 0x5BD68A, 33: 0xE3B341, 34: 0x6C9EF8, 35: 0xC792EA, 36: 0x40B8AF, 37: 0xD5D9E6,
    90: 0x5D6683, 91: 0xFF7A80, 92: 0x7AE6A0, 93: 0xF5C451, 94: 0x8AB4FF, 95: 0xD7A6F5, 96: 0x6FD6CC, 97: 0xF4F6FB,
]

/// Splits rendered ANSI into rows of cells.
func parse(_ ansi: String) -> [[Cell]] {
    var rows: [[Cell]] = []
    for line in ansi.split(separator: "\n", omittingEmptySubsequences: false) {
        var row: [Cell] = []
        var style = Cell()
        var rest = Substring(line)
        while let character = rest.first {
            if character == "\u{1B}", let match = rest.prefixMatch(of: #/\x1B\[([0-9;]*)m/#) {
                var codes = match.1.split(separator: ";").compactMap { Int($0) }[...]
                if codes.isEmpty { codes = [0] }
                while let code = codes.popFirst() {
                    switch code {
                    case 0: style = Cell()
                    case 1: style.bold = true
                    case 2: style.dim = true
                    case 22: (style.bold, style.dim) = (false, false)
                    case 7: style.inverse = true
                    case 27: style.inverse = false
                    case 39: style.foreground = nil
                    case 49: style.background = nil
                    case 38, 48:
                        guard codes.popFirst() == 2, codes.count >= 3 else { break }
                        let rgb = UInt32(codes.removeFirst() << 16 | codes.removeFirst() << 8 | codes.removeFirst())
                        if code == 38 { style.foreground = rgb } else { style.background = rgb }
                    case 30...37, 90...97: style.foreground = basic[code]
                    case 40...47, 100...107: style.background = basic[code - 10]
                    default: break
                    }
                }
                rest = rest[match.range.upperBound...]
            } else {
                var cell = style
                cell.character = character
                row.append(cell)
                rest = rest.dropFirst()
            }
        }
        rows.append(row)
    }
    return rows
}

/// Mixes two colours, `amount` of the way from `a` to `b`.
func mix(_ a: UInt32, _ b: UInt32, _ amount: Double) -> UInt32 {
    [16, 8, 0].reduce(0) { result, shift in
        let x = Double((a >> UInt32(shift)) & 0xFF)
        let y = Double((b >> UInt32(shift)) & 0xFF)
        return result | UInt32((x + (y - x) * amount).rounded()) << UInt32(shift)
    }
}

/// Draws box-drawing and block characters as shapes, so lines join across cells.
/// Returns false for characters the font should draw.
func drawShape(_ character: Character, in cell: NSRect, color tint: NSColor) -> Bool {
    let mid = NSPoint(x: cell.midX.rounded(.down) + 0.5, y: cell.midY.rounded(.down) + 0.5)
    let path = NSBezierPath()
    path.lineWidth = 1.2
    switch character {
    case "─", "━":
        path.lineWidth = character == "━" ? 3 : 1.2
        path.move(to: NSPoint(x: cell.minX, y: mid.y))
        path.line(to: NSPoint(x: cell.maxX, y: mid.y))
    case "│", "┃":
        path.lineWidth = character == "┃" ? 3 : 1.2
        path.move(to: NSPoint(x: mid.x, y: cell.minY))
        path.line(to: NSPoint(x: mid.x, y: cell.maxY))
    case "╭", "╮", "╰", "╯", "┌", "┐", "└", "┘":
        let right = "╭╰┌└".contains(character)
        let down = "╭╮┌┐".contains(character)
        let edgeX = right ? cell.maxX : cell.minX
        let edgeY = down ? cell.minY : cell.maxY
        path.move(to: NSPoint(x: edgeX, y: mid.y))
        if "╭╮╰╯".contains(character) {
            let radius = min(cell.width, cell.height) / 2
            let corner = NSPoint(x: mid.x, y: mid.y)
            path.line(to: NSPoint(x: mid.x + (right ? radius : -radius), y: mid.y))
            path.curve(
                to: NSPoint(x: mid.x, y: mid.y + (down ? -radius : radius)), controlPoint1: corner, controlPoint2: corner)
        } else {
            path.line(to: mid)
        }
        path.line(to: NSPoint(x: mid.x, y: edgeY))
    case "▀", "▄", "▌", "█":
        tint.setFill()
        switch character {
        case "▀": NSRect(x: cell.minX, y: cell.midY, width: cell.width, height: cell.height / 2).fill()
        case "▄": NSRect(x: cell.minX, y: cell.minY, width: cell.width, height: cell.height / 2).fill()
        case "▌": NSRect(x: cell.minX, y: cell.minY, width: cell.width / 2, height: cell.height).fill()
        default: cell.fill()
        }
        return true
    default:
        return false
    }
    tint.setStroke()
    path.stroke()
    return true
}

/// Draws `rows` with the top-left at `origin`, returning the size used.
func drawScreen(_ rows: [[Cell]], at origin: NSPoint, cellWidth: Double, cellHeight: Double, canvasHeight: Double, background: UInt32) {
    let regular = NSFont.monospacedSystemFont(ofSize: 13.5, weight: .regular)
    let bold = NSFont.monospacedSystemFont(ofSize: 13.5, weight: .bold)
    let defaultForeground: UInt32 = 0xE6E9F2
    for (rowIndex, row) in rows.enumerated() {
        for (column, cell) in row.enumerated() {
            let frame = NSRect(
                x: origin.x + Double(column) * cellWidth,
                y: canvasHeight - origin.y - Double(rowIndex + 1) * cellHeight, width: cellWidth, height: cellHeight)
            var foreground = cell.foreground ?? defaultForeground
            var back = cell.background
            if cell.inverse {
                (foreground, back) = (back ?? background, foreground)
            }
            if cell.dim {
                foreground = mix(foreground, back ?? background, 0.45)
            }
            if let back {
                color(back).setFill()
                frame.insetBy(dx: -0.25, dy: -0.25).fill()
            }
            guard cell.character != " ", !drawShape(cell.character, in: frame, color: color(foreground)) else { continue }
            let font = cell.bold ? bold : regular
            let text = NSAttributedString(
                string: String(cell.character), attributes: [.font: font, .foregroundColor: color(foreground)])
            text.draw(at: NSPoint(x: frame.minX, y: frame.minY + (cellHeight - font.ascender + font.descender) / 2 - font.descender))
        }
    }
}

// MARK: The banner

guard let ansi = try? String(contentsOf: assets.appending(path: "banner-screen.ansi"), encoding: .utf8) else {
    FileHandle.standardError.write(Data("banner-screen.ansi is missing; see the top of this script\n".utf8))
    exit(1)
}
let screen = parse(ansi).filter { !$0.isEmpty }

render("banner.png", width: 1280, height: 640) {
    let canvas = NSRect(x: 0, y: 0, width: 1280, height: 640)
    NSGradient(starting: color(0x0B0F1C), ending: color(0x141B33))?.draw(in: canvas, angle: 90)

    // A few pixel stars over the cat.
    for (x, y, hex) in [(1010.0, 60.0, 0xE3B341), (1180, 110, 0x40B8AF), (1090, 180, 0xE3B341), (1225, 250, 0xF4F6FB),
                        (960, 300, 0x40B8AF), (1150, 40, 0xF4F6FB)] as [(Double, Double, UInt32)] {
        color(hex, alpha: 0.8).setFill()
        NSRect(x: x, y: 640 - y, width: 5, height: 5).fill()
    }

    let title = NSAttributedString(
        string: "Tag Agent",
        attributes: [.font: NSFont.systemFont(ofSize: 46, weight: .bold), .foregroundColor: color(0xF4F6FB)])
    title.draw(at: NSPoint(x: 60, y: 640 - 42 - 46))
    let subtitle = NSAttributedString(
        string: "A coding-agent harness for the terminal, written in Swift",
        attributes: [.font: NSFont.systemFont(ofSize: 19), .foregroundColor: color(0xA9B1CC)])
    subtitle.draw(at: NSPoint(x: 62, y: 640 - 104 - 19))

    // The terminal window.
    let cellWidth = 8.2
    let cellHeight = 16.0
    let columns = Double(screen.map(\.count).max() ?? 0)
    let windowBackground: UInt32 = 0x0D1120
    let window = NSRect(
        x: 60, y: 640 - 150 - (34 + Double(screen.count) * cellHeight + 12),
        width: columns * cellWidth + 24, height: 34 + Double(screen.count) * cellHeight + 12)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0x000000, alpha: 0.5)
    shadow.shadowBlurRadius = 30
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    let windowPath = NSBezierPath(roundedRect: window, xRadius: 12, yRadius: 12)
    color(windowBackground).setFill()
    windowPath.fill()
    NSGraphicsContext.restoreGraphicsState()
    color(0x2A3150).setStroke()
    windowPath.lineWidth = 1
    windowPath.stroke()
    for (index, light) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
        color(UInt32(light)).setFill()
        NSBezierPath(ovalIn: NSRect(x: window.minX + 16 + Double(index) * 20, y: window.maxY - 23, width: 12, height: 12)).fill()
    }
    drawScreen(
        screen, at: NSPoint(x: window.minX + 12, y: 640 - window.maxY + 34), cellWidth: cellWidth,
        cellHeight: cellHeight, canvasHeight: 640, background: windowBackground)

    // The cat, sitting on the same floor as the window.
    let scale = 14.0
    let catX = window.maxX + (1280 - window.maxX - width * scale) / 2
    drawCat(at: NSPoint(x: catX, y: 640 - window.minY - height * scale), scale: scale, canvasHeight: 640)
}
