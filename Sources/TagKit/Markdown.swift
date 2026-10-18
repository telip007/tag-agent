import Stipple

/// Just enough Markdown for chat replies, drawn in the terminal's own terms:
/// `code` in turquoise, **bold** in bold, headings bold, and fenced code blocks
/// indented and turquoise, with the fences themselves left out. Everything else
/// is shown as written.
@MainActor
enum Markdown {
    /// `markdown` as styled text.
    static func text(_ markdown: String) -> Text {
        var result = Text("")
        var isInFence = false
        var isFirstLine = true
        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.trimmingPrefix(while: \.isWhitespace).hasPrefix("```") {
                isInFence.toggle()
                continue
            }
            let styled: Text
            if isInFence {
                styled = Text("  \(line)").foregroundStyle(Theme.tile)
            } else if let heading = heading(line) {
                styled = Text(heading).bold()
            } else {
                styled = inline(String(line))
            }
            result = isFirstLine ? styled : result + Text("\n") + styled
            isFirstLine = false
        }
        return result
    }

    /// The title of a `#`–`######` heading line, or `nil`.
    private static func heading(_ line: Substring) -> String? {
        let hashes = line.prefix { $0 == "#" }
        guard (1...6).contains(hashes.count), line.dropFirst(hashes.count).first == " " else {
            return nil
        }
        return String(line.dropFirst(hashes.count + 1))
    }

    /// Inline `code` and **bold**. An unclosed marker is shown as written.
    static func inline(_ line: String) -> Text {
        var result = Text("")
        var rest = Substring(line)
        while !rest.isEmpty {
            guard let marker = rest.firstRange(of: /`|\*\*/) else {
                return result + Text(rest)
            }
            let delimiter = rest[marker]
            let afterMarker = rest[marker.upperBound...]
            guard let closing = afterMarker.firstRange(of: delimiter), closing.lowerBound > afterMarker.startIndex
            else {
                return result + Text(rest)
            }
            let inner = Text(afterMarker[..<closing.lowerBound])
            result =
                result + Text(rest[..<marker.lowerBound])
                + (delimiter == "`" ? inner.foregroundStyle(Theme.tile) : inner.bold())
            rest = afterMarker[closing.upperBound...]
        }
        return result
    }
}
