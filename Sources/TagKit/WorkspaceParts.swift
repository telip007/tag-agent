import Foundation
import Stipple

/// The look: the terminal's own colours with a gold accent, turquoise for
/// code, green and red for diffs, and dim rules.
enum Theme {
    static let accent = Color(red: 227, green: 179, blue: 65)
    static let tile = Color(red: 64, green: 184, blue: 175)
    static let rule = Color.gray
    static let selection = Color(red: 58, green: 62, blue: 80)
    static let added = Color.green
    static let removed = Color.red
}

extension View {
    /// A rounded pane with its title set into the top border.
    func pane(title: String, isActive: Bool) -> some View {
        padding(.horizontal, 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .border(.rounded, color: isActive ? Theme.accent : Theme.rule)
            .overlay(alignment: .topLeading) {
                Text(" \(title) ").foregroundStyle(isActive ? Theme.accent : Theme.rule).padding(.leading, 2)
            }
    }
}

/// The conversation in a scroll view. A short conversation starts at the top;
/// once it fills the pane, the view follows the newest block until the user
/// scrolls up (wheel, Page Up), and pins again back at the bottom. A click on
/// a block expands or collapses it.
struct TranscriptPane: View {
    let session: ChatSession
    let selected: Int?
    @Binding var position: ScrollPosition
    @State private var hovered: Int?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                ForEach(session.blocks) { block in
                    BlockRow(
                        block: block,
                        isExpanded: session.expanded.contains(block.id),
                        isSelected: block.id == selected,
                        isHovered: block.id == hovered,
                    )
                    .id(block.id)
                    .onTapGesture { session.toggle(block.id) }
                    .onHover { isHovering in
                        if isHovering {
                            hovered = block.id
                        } else if hovered == block.id {
                            hovered = nil
                        }
                    }
                }
            }
            .padding(.bottom, 1)
        }
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .scrollPosition($position)
        .scrollOnPageKeys()
    }
}

/// A block of the session: reads the block's content itself, so the pane
/// doesn't rebuild when one block changes, and is equal to the same row with
/// the same flags, so the pane rebuilding leaves the other rows alone.
struct BlockRow: View, Equatable {
    let block: LiveBlock
    let isExpanded: Bool
    let isSelected: Bool
    let isHovered: Bool

    var body: some View {
        let block = TranscriptBlock(id: block.id, content: block.content)
        BlockView(block: block, isExpanded: isExpanded, isSelected: isSelected || (isHovered && block.isExpandable))
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.block === rhs.block && lhs.isExpanded == rhs.isExpanded && lhs.isSelected == rhs.isSelected
            && lhs.isHovered == rhs.isHovered
    }
}

/// One block, with a highlight while it is selected in browse mode.
struct BlockView: View {
    /// Edits longer than this show their first lines until expanded.
    static let collapsedEditLines = 8
    /// Lines of a tool's output an expanded tray shows.
    static let outputLines = 6
    /// Lines of reasoning shown while the model is still reasoning.
    static let reasoningLines = 3

    let block: TranscriptBlock
    let isExpanded: Bool
    let isSelected: Bool

    var body: some View {
        if isSelected {
            content.frame(maxWidth: .infinity, alignment: .leading).background(Theme.selection)
        } else {
            content
        }
    }

    @ViewBuilder private var content: some View {
        switch block.content {
        case .user(let text):
            HStack {
                Text("▌ ").foregroundStyle(Theme.accent)
                Text(text).bold()
            }
            .padding(.top, 1)
        case .reasoning(let reasoning):
            ReasoningView(reasoning: reasoning, isExpanded: isExpanded).padding(.leading, 2).padding(.top, 1)
        case .reply(let text):
            Markdown.view(text).padding(.leading, 2).padding(.top, 1)
        case .tools(let runs):
            ToolTray(runs: runs, isExpanded: isExpanded).padding(.leading, 2).padding(.top, 1)
        case .edit(let edit):
            EditCard(edit: edit, isExpanded: isExpanded).padding(.leading, 2).padding(.top, 1)
        }
    }
}

/// A run of tool calls: one summary line, or every call (with the start of
/// its output) while running or expanded.
struct ToolTray: View {
    let runs: [ToolRun]
    let isExpanded: Bool

    private var isRunning: Bool {
        runs.contains { $0.state == .running }
    }

    var body: some View {
        if isRunning || isExpanded {
            VStack(alignment: .leading) {
                ForEach(Array(runs.enumerated()), id: \.offset) { _, run in
                    VStack(alignment: .leading) {
                        Self.line(for: run)
                        if isExpanded, !run.output.isEmpty {
                            Text(Self.preview(run.output)).dim().padding(.leading, 4)
                        }
                    }
                }
            }
        } else {
            summary
        }
    }

    /// `▸ 3 tools · 4.2s  search · read · bash`, red when one failed.
    private var summary: Text {
        let failed = runs.contains { $0.state == .failed }
        let total = runs.compactMap(\.duration).reduce(Duration.zero, +)
        let count = runs.count == 1 ? "1 tool" : "\(runs.count) tools"
        return Text("▸ ").foregroundStyle(failed ? Theme.removed : Theme.accent)
            + Text("\(count) · \(ChatSession.seconds(total))")
            + Text("  " + runs.map(\.name).joined(separator: " · ")).dim()
    }

    static func line(for run: ToolRun) -> Text {
        let mark: Text =
            switch run.state {
            case .running: Text("◌ ").foregroundStyle(Theme.accent)
            case .succeeded: Text("✓ ").foregroundStyle(Theme.added)
            case .failed: Text("✗ ").foregroundStyle(Theme.removed)
            }
        let duration = run.duration.flatMap { $0 >= ChatSession.noticeableDuration ? $0 : nil }
        return mark + Text(run.name) + Text(run.summary.isEmpty ? "" : "  \(run.summary)").dim()
            + Text(duration.map { "  \(ChatSession.seconds($0))" } ?? "").foregroundStyle(Theme.accent)
    }

    /// The first lines of a tool's output, with a count of the rest.
    static func preview(_ output: String) -> String {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
        let shown = lines.prefix(BlockView.outputLines).joined(separator: "\n")
        let rest = lines.count - BlockView.outputLines
        return rest > 0 ? shown + "\n… \(rest) more lines" : shown
    }
}

/// The model's reasoning, dim: its latest lines while it reasons, then one
/// line with how long it took, all of it when expanded.
struct ReasoningView: View {
    let reasoning: Reasoning
    let isExpanded: Bool

    var body: some View {
        let text = reasoning.text.trimmingCharacters(in: .whitespacesAndNewlines)
        VStack(alignment: .leading) {
            header
            if isExpanded {
                Text(text).dim().padding(.leading, 2)
            } else if reasoning.duration == nil {
                Text(Self.tail(of: text)).dim().lineLimit(BlockView.reasoningLines).truncationMode(.head)
                    .padding(.leading, 2)
            }
        }
    }

    /// Enough of the end of `text` to fill the lines shown while the model
    /// reasons, so a long reasoning isn't wrapped whole on every new word.
    static func tail(of text: String) -> String {
        let limit = BlockView.reasoningLines * 400
        return text.count > limit ? String(text.suffix(limit)) : text
    }

    /// `◌ thinking` while it reasons, then `▸ thought · 3.1s`.
    private var header: Text {
        guard let duration = reasoning.duration else {
            return Text("◌ ").foregroundStyle(Theme.accent) + Text("thinking").dim()
        }
        return Text("▸ ").foregroundStyle(Theme.rule) + Text("thought · \(ChatSession.seconds(duration))").dim()
    }
}

/// A change to a file as a small diff card.
struct EditCard: View {
    let edit: FileEdit
    let isExpanded: Bool

    var body: some View {
        let shown = isExpanded ? edit.lines : Array(edit.lines.prefix(BlockView.collapsedEditLines))
        VStack(alignment: .leading) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, line in
                switch line {
                case .removed(let text): Text("- \(text)").foregroundStyle(Theme.removed)
                case .added(let text): Text("+ \(text)").foregroundStyle(Theme.added)
                }
            }
            if edit.lines.count > shown.count {
                Text("… \(edit.lines.count - shown.count) more lines").dim()
            }
            if edit.lines.isEmpty {
                Text("no line changes").dim()
            }
        }
        .padding(.horizontal, 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .border(.single, color: Theme.rule)
        .overlay(alignment: .topLeading) {
            Text(" \(edit.path) ").padding(.leading, 1)
        }
        .overlay(alignment: .topTrailing) {
            let counts = Text(" +\(edit.added)").foregroundStyle(Theme.added)
            (counts + Text(" −\(edit.removed) ").foregroundStyle(Theme.removed)).padding(.trailing, 1)
        }
    }
}

/// The side panel: the model, how full its context is, what the session has
/// cost and how long it has run, and the files it changed.
struct SessionPanel: View {
    static let width = 30
    static let gaugeWidth = width - 4

    let session: ChatSession

    var body: some View {
        VStack(alignment: .leading) {
            if let status = session.status {
                Text(status.model.name).bold()
                Text(status.folder).dim()
                Text(" ")
                gauge(status)
                Text("\(status.contextUsage) tokens").dim()
                Text("\(status.money) · \(Self.clock(session.elapsed))").dim()
            } else {
                Text("connecting…").dim()
            }
            Text(" ")
            Text("files").foregroundStyle(Theme.rule)
            if session.files.isEmpty {
                Text("no changes yet").dim()
            }
            ForEach(Array(session.files.enumerated()), id: \.offset) { _, file in
                HStack {
                    Text(Self.fileName(file.path)).truncationMode(.head)
                    Spacer(minLength: 1)
                    Text("+\(file.added)").foregroundStyle(Theme.added)
                    Text(" −\(file.removed)").foregroundStyle(Theme.removed)
                }
            }
            if !session.queued.isEmpty {
                Text(" ")
                Text("queued").foregroundStyle(Theme.rule)
                ForEach(Array(session.queued.enumerated()), id: \.offset) { _, message in
                    Text("· \(message)").lineLimit(1).dim()
                }
            }
        }
    }

    /// `▰▰▰▱▱▱▱ 12%`, gold past half and red past 80%.
    private func gauge(_ status: StatusLine) -> Text {
        guard let fraction = status.contextFraction else {
            return Text("context window unknown").dim()
        }
        let clamped = min(max(fraction, 0), 1)
        let cells = Self.gaugeWidth - 5
        let filled = clamped > 0 ? max(1, Int((clamped * Double(cells)).rounded())) : 0
        let color: Color = clamped < 0.5 ? Theme.tile : clamped < 0.8 ? Theme.accent : Theme.removed
        return Text(String(repeating: "━", count: filled)).foregroundStyle(color)
            + Text(String(repeating: "━", count: cells - filled)).foregroundStyle(Theme.selection)
            + Text(" \(Int((clamped * 100).rounded()))%").dim()
    }

    /// `42s`, `4m 12s`, `1h 03m`.
    static func clock(_ duration: Duration) -> String {
        let seconds = Int(duration / .seconds(1))
        if seconds < 60 {
            return "\(seconds)s"
        }
        if seconds < 3_600 {
            return "\(seconds / 60)m \(twoDigits(seconds % 60))s"
        }
        return "\(seconds / 3_600)h \(twoDigits(seconds % 3_600 / 60))m"
    }

    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }

    /// The last path component, as the panel has little room.
    static func fileName(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }
}

/// The bottom line: key hints or a warning on the left, the agent's activity
/// on the right. Each hint can be clicked as well as typed.
struct Footer: View {
    /// A key, what it does, and what a click on it does.
    struct Key {
        let key: String
        let label: String
        let action: @MainActor () -> Void
    }

    enum Hint {
        case keys([Key])
        case warning(String)
    }

    static let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

    let session: ChatSession
    let hint: Hint

    var body: some View {
        HStack {
            hints.padding(.leading, 1)
            Spacer(minLength: 2)
            if let activity = session.activity, let start = session.activityStart {
                TimelineView(.periodic(every: .milliseconds(80))) { context in
                    let elapsed = ContinuousClock.now - start
                    Text("\(Self.frames[context.frame % Self.frames.count]) ").foregroundStyle(Theme.accent)
                        + Text(activity).dim()
                        + Text(elapsed >= ChatSession.noticeableDuration ? "  \(ChatSession.seconds(elapsed))" : "")
                        .dim()
                }
                .lineLimit(1)
                .padding(.trailing, 1)
            }
        }
    }

    @ViewBuilder private var hints: some View {
        switch hint {
        case .warning(let text):
            Text(text).foregroundStyle(Theme.accent)
        case .keys(let keys):
            HStack {
                ForEach(Array(keys.enumerated()), id: \.offset) { offset, key in
                    if offset > 0 {
                        Text(" · ").dim()
                    }
                    FooterKey(key: key)
                }
            }
        }
    }
}

/// One clickable hint, lit up while the pointer is over it.
struct FooterKey: View {
    let key: Footer.Key
    @State private var isHovered = false

    var body: some View {
        (Text(key.key).foregroundStyle(isHovered ? Theme.accent : nil)
            + Text(" \(key.label)").foregroundStyle(isHovered ? Theme.accent : nil).dim(!isHovered))
            .onTapGesture(perform: key.action)
            .onHover { isHovered = $0 }
    }
}

extension TranscriptBlock {
    /// Whether a click changes the block: trays, edits and reasoning expand.
    var isExpandable: Bool {
        switch content {
        case .tools, .edit, .reasoning: true
        case .user, .reply: false
        }
    }

    /// The block as plain text, for copying.
    var plainText: String {
        switch content {
        case .user(let text), .reply(let text):
            return text
        case .reasoning(let reasoning):
            return reasoning.text
        case .tools(let runs):
            return runs.map { "\($0.name) \($0.summary)\n\($0.output)" }.joined(separator: "\n\n")
        case .edit(let edit):
            let lines = edit.lines.map { line in
                switch line {
                case .removed(let text): "- \(text)"
                case .added(let text): "+ \(text)"
                }
            }
            return ([edit.path] + lines).joined(separator: "\n")
        }
    }
}
