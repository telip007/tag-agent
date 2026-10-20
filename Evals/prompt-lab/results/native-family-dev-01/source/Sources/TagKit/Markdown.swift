import Stipple

/// Just enough Markdown for chat replies, drawn in the terminal's own terms:
/// `code` in turquoise, **bold** in bold, headings bold, and fenced code blocks
/// indented and turquoise, with the fences themselves left out. Everything else
/// is shown as written.
@MainActor
enum Markdown {
    /// `markdown` as styled text, one view per line: a reply being streamed
    /// grows its last line, so only that line is laid out again.
    static func view(_ markdown: String) -> some View {
        let lines = lines(markdown)
        return VStack(alignment: .leading) {
            ForEach(lines.indices, id: \.self) { index in
                lines[index]
            }
        }
    }

    /// Each line of `markdown`, styled. A blank line is a space, so it keeps
    /// its row.
    static func lines(_ markdown: String) -> [Text] {
        var result: [Text] = []
        var isInFence = false
        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.trimmingPrefix(while: \.isWhitespace).hasPrefix("```") {
                isInFence.toggle()
                continue
            }
            if isInFence {
                result.append(Text("  \(line)").foregroundStyle(Theme.tile))
            } else if let heading = heading(line) {
                result.append(Text(heading).bold())
            } else {
                result.append(line.isEmpty ? Text(" ") : inline(String(line)))
            }
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
        // Most lines have no markers; skip the regex, which scans the whole
        // line again each time a streamed reply grows.
        guard line.contains("`") || line.contains("**") else {
            return Text(line)
        }
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
