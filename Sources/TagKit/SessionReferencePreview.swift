import Foundation
import SessionKit
import Stipple

/// A user confirms the actual copied excerpts, independently from switching sessions.
struct SessionReferencePreview: View {
    let excerpts: [SessionReference]
    let width: Int
    let height: Int
    let error: String?
    @Binding var position: ScrollPosition
    let attach: @MainActor () -> Void
    let cancel: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading) {
            Text(SessionPresentation.clean(excerpts.first?.source.title ?? "Session")).bold().lineLimit(1)
            Text("\(excerpts.count) excerpts · \(SessionReferences.render(excerpts).utf8.count) / 16384 bytes").dim()
                .lineLimit(1)
            Text("Historical evidence · attached to your next message").dim().lineLimit(1)
            Text(" ")
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(excerpts.enumerated()), id: \.offset) { _, excerpt in
                        VStack(alignment: .leading) {
                            Text(
                                "\(excerpt.source.sessionID.uuidString.prefix(8).lowercased()) · entry \(excerpt.source.sequence) · \(excerpt.source.role)"
                            )
                            .foregroundStyle(Theme.accent)
                            Text(SessionPresentation.clean(excerpt.text))
                        }
                    }
                }
            }.frame(height: max(4, height - 10), alignment: .topLeading)
                .scrollPosition($position)
            Text(error ?? "Copied excerpts stay with this draft until you send.")
                .foregroundStyle(error == nil ? Theme.rule : Theme.removed).lineLimit(1)
            KeyHints(keys: [
                Footer.Key(key: "↑↓", label: "scroll") { position.scrollBy(lines: 1) },
                Footer.Key(key: "↵", label: "attach") { attach() },
                Footer.Key(key: "esc", label: "back") { cancel() },
            ])
        }.modal(title: "reference preview", width: width)
    }
}

enum SessionPresentation {
    /// Saved content cannot introduce terminal escape sequences into labels/previews.
    static func clean(_ text: String) -> String {
        String(
            text.unicodeScalars.map { scalar -> Character in
                if scalar.value == 0x1B { return "␛" }
                if CharacterSet.controlCharacters.contains(scalar), scalar != "\n", scalar != "\t" { return " " }
                return Character(scalar)
            })
    }

    static func age(_ date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        if seconds < 86_400 { return "\(seconds / 3600)h ago" }
        return "\(seconds / 86_400)d ago"
    }

    static func excerpts(_ excerpts: [SessionReference]) -> String {
        guard !excerpts.isEmpty else { return "No completed exchange matches this search." }
        let text = excerpts.suffix(2).map {
            ($0.source.role == "user" ? "you" : $0.source.role == "assistant" ? "tag" : "tool")
                + " · entry \($0.source.sequence)\n" + $0.text
        }.joined(separator: "\n\n")
        return clean(SessionReferences.truncate(text, bytes: 2000))
    }
}
