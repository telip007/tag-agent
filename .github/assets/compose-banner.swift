// Composes .github/assets/banner.png from a text-free background illustration
// (banner-background.png, generated with Codex) and exact text: the title and
// a Tag Agent session in the colours the CLI uses, with logo.png (the mascot,
// from the same folder as the background) beside the title.
//
//   swift .github/assets/compose-banner.swift .github/assets/banner-background.png .github/assets/banner.png
//
// Keep the session in sync with the tools and the CLI's output format.

import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3, let background = NSImage(contentsOfFile: arguments[1]) else {
    FileHandle.standardError.write(Data("usage: compose-banner.swift <background.png> <out.png>\n".utf8))
    exit(1)
}

let width = 1280.0
let height = 640.0
guard
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height), bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    ),
    let context = NSGraphicsContext(bitmapImageRep: bitmap)
else {
    exit(1)
}
NSGraphicsContext.current = context

/// Converts top-left based coordinates (as used in the illustration brief) to AppKit's.
func rect(x: Double, y: Double, width rectWidth: Double, height rectHeight: Double) -> NSRect {
    NSRect(x: x, y: height - y - rectHeight, width: rectWidth, height: rectHeight)
}

func color(_ hex: UInt32, alpha: Double = 1) -> NSColor {
    NSColor(
        srgbRed: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
        blue: Double(hex & 0xFF) / 255, alpha: alpha
    )
}

func draw(_ text: String, at point: NSPoint, font: NSFont, color: NSColor) {
    NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        .draw(at: NSPoint(x: point.x, y: height - point.y - font.ascender))
}

background.draw(in: NSRect(x: 0, y: 0, width: width, height: height))

// Mascot tile beside the title.
let logoURL = URL(filePath: arguments[1]).deletingLastPathComponent().appending(path: "logo.png")
if let logo = NSImage(contentsOf: logoURL) {
    let tile = rect(x: 60, y: 34, width: 84, height: 84)
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: tile, xRadius: 18, yRadius: 18).addClip()
    logo.draw(in: tile)
    NSGraphicsContext.restoreGraphicsState()
}

// Title.
draw(
    "Tag Agent", at: NSPoint(x: 164, y: 42),
    font: .systemFont(ofSize: 46, weight: .bold), color: color(0xF4F6FB)
)
draw(
    "A coding-agent harness for the terminal, written in Swift", at: NSPoint(x: 166, y: 98),
    font: .systemFont(ofSize: 19, weight: .regular), color: color(0xA9B1CC)
)

// Terminal window (x 60…630, y 160…580), over the faint left part of the illustration.
let window = rect(x: 60, y: 160, width: 570, height: 420)
let windowPath = NSBezierPath(roundedRect: window, xRadius: 14, yRadius: 14)
color(0x0A0E1A, alpha: 0.92).setFill()
windowPath.fill()
color(0x2EC4B6, alpha: 0.28).setStroke()
windowPath.lineWidth = 1.5
windowPath.stroke()
for (index, light) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
    color(UInt32(light)).setFill()
    NSBezierPath(ovalIn: rect(x: 84 + Double(index) * 22, y: 178, width: 13, height: 13)).fill()
}

// A session, coloured like the CLI: You (bright blue), tool (bright green), Agent (bright yellow).
let mono = NSFont.monospacedSystemFont(ofSize: 15.5, weight: .regular)
let you = color(0x7AA2FF)
let tool = color(0x4ADE80)
let agent = color(0xF5C451)
let plain = color(0xE6E9F2)
let dim = color(0x6C7693)
let string = color(0xFFA066)

let session: [[(String, NSColor)]] = [
    [("$ ", dim), ("swift run Tag", plain)],
    [("Chat with Tag Agent (use 'ctrl-c' to quit)", dim)],
    [],
    [("You", you), (": make fizzbuzz.js stop at 10 and run it", plain)],
    [("tool", tool), (": read_file({\"path\":", plain), ("\"fizzbuzz.js\"", string), ("})", plain)],
    [("tool", tool), (": code_search({\"pattern\":", plain), ("\"<= 15\"", string), ("})", plain)],
    [("tool", tool), (": edit_file({\"path\":", plain), ("\"fizzbuzz.js\"", string), (", …})", plain)],
    [("tool", tool), (": bash({\"command\":", plain), ("\"node fizzbuzz.js\"", string), ("})", plain)],
    [("Agent", agent), (": Done. It now counts from 1 to 10 and", plain)],
    [("       ends with \"Buzz\".", plain)],
    [],
    [("You", you), (": ", plain), ("▍", plain)],
]
var lineY = 222.0
for line in session {
    var x = 88.0
    for (text, tint) in line {
        draw(text, at: NSPoint(x: x, y: lineY), font: mono, color: tint)
        x += NSAttributedString(string: text, attributes: [.font: mono]).size().width
    }
    lineY += 27
}

NSGraphicsContext.current = nil
guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(filePath: arguments[2]))
print("wrote \(arguments[2])")
