import ModelKit
import Stipple

/// The `/model` overlay: a search box over every connected provider's
/// models, recent ones first, then each provider's.
///
/// ```text
/// ╭─ model ─────────────────────────────────────────────╮
/// │ › gpt                                               │
/// │                                                     │
/// │ recent                                              │
/// │ ● GPT-5.5 Codex             chatgpt (codex) included│
/// │ openrouter                                          │
/// │   GPT-5.5                   400k ctx    $1.25 / $10 │
/// │                                                     │
/// │ reasoning ◂ medium ▸                                │
/// │ ↵ use · ←→ effort · ^a add provider · esc close     │
/// ╰─────────────────────────────────────────────────────╯
/// ```
///
/// It draws only the rows in view and always as many lines, so the box
/// doesn't jump while the list filters. Keys reach it through its owner,
/// which calls ``ModelPickerState/handle(_:)``.
struct ModelPicker: View {
    let state: ModelPickerState
    let width: Int
    let perform: @MainActor (PickerAction) -> Void

    var body: some View {
        let inner = width - 4
        VStack(alignment: .leading) {
            SearchLine(query: state.query, placeholder: "search models", isLoading: state.isLoading)
            Text(" ")
            list(width: inner)
            Text(" ")
            effortLine
            hints
        }
        .modal(title: "model", width: width)
    }

    @ViewBuilder private func list(width: Int) -> some View {
        let window = state.window(limit: state.rowLimit)
        VStack(alignment: .leading) {
            if state.rows.isEmpty {
                Text(emptyMessage).dim()
            }
            ForEach(Array(window), id: \.self) { index in
                row(index, width: width)
            }
        }
        .frame(height: state.rowLimit, alignment: .topLeading)
    }

    @ViewBuilder private func row(_ index: Int, width: Int) -> some View {
        switch state.rows[index] {
        case .header(let title):
            Text(title).foregroundStyle(Theme.rule)
        case .failure(let provider, let message):
            Text("✗ \(PickerList.label(provider)): \(message)").foregroundStyle(Theme.removed).lineLimit(1)
        case .model(let entry, let isRecent):
            ModelRow(
                entry: entry,
                isRecent: isRecent,
                isCurrent: entry.ref == state.current,
                isHighlighted: index == state.highlighted,
                width: width,
            )
            .onTapGesture { [state] in state.highlight(index) }
            .onTapGesture(count: 2) { [state, perform] in
                state.highlight(index)
                perform(.use(entry, effort: state.effort(for: entry)))
            }
        }
    }

    private var emptyMessage: String {
        if state.isLoading {
            return "loading models…"
        }
        if state.hasNoModels {
            return "No models yet. ^a connects a provider."
        }
        return "No model matches “\(state.query)”."
    }

    /// Why the last choice failed, or `reasoning ◂ medium ▸` for a model
    /// that takes an effort; a blank line otherwise.
    private var effortLine: Text {
        if let error = state.error {
            return Text("✗ ").foregroundStyle(Theme.removed) + Text(error)
        }
        guard let entry = state.highlightedEntry, let effort = state.effort(for: entry) else {
            return Text(" ")
        }
        return Text("reasoning ").foregroundStyle(Theme.rule) + Text("◂ ").dim()
            + Text(effort).foregroundStyle(Theme.accent) + Text(" ▸").dim()
    }

    private var hints: some View {
        let takesEffort = state.highlightedEntry?.reasoningEfforts.isEmpty == false
        let keys =
            [
                Footer.Key(key: "↵", label: "use") { [state, perform] in
                    if let entry = state.highlightedEntry {
                        perform(.use(entry, effort: state.effort(for: entry)))
                    }
                }
            ]
            + (takesEffort ? [Footer.Key(key: "←→", label: "effort") { [state] in state.cycleEffort(by: 1) }] : [])
            + [
                Footer.Key(key: "^a", label: "add provider") { [perform] in perform(.connect) },
                Footer.Key(key: "esc", label: "close") { [perform] in perform(.close) },
            ]
        return KeyHints(keys: keys)
    }
}

/// One model: the mark, the name, its provider or context, and its price.
struct ModelRow: View, Equatable {
    static let detailWidth = 16
    static let priceWidth = 13

    let entry: ModelEntry
    let isRecent: Bool
    let isCurrent: Bool
    let isHighlighted: Bool
    let width: Int

    var body: some View {
        let detail = isRecent ? PickerList.label(entry.ref.provider) : PickerList.context(entry)
        let nameWidth = max(width - 2 - Self.detailWidth - Self.priceWidth, 8)
        let line = HStack {
            Text(isCurrent ? "● " : "  ").foregroundStyle(Theme.accent)
            Text(entry.name).foregroundStyle(isHighlighted ? Theme.accent : nil).bold(isHighlighted).lineLimit(1)
                .frame(width: nameWidth, alignment: .leading)
            Text(detail).dim().lineLimit(1).frame(width: Self.detailWidth, alignment: .leading)
            Text(PickerList.price(entry.pricing)).dim().lineLimit(1)
                .frame(width: Self.priceWidth, alignment: .trailing)
        }
        if isHighlighted {
            line.background(Theme.selection)
        } else {
            line
        }
    }
}

/// `› query` with a block caret, or the placeholder while empty.
struct SearchLine: View, Equatable {
    let query: String
    let placeholder: String
    var isLoading = false

    var body: some View {
        HStack {
            Text("› ").foregroundStyle(Theme.accent)
            Text(query)
            Text(" ").background(Theme.accent)
            if query.isEmpty {
                Text(placeholder).dim()
            }
            if isLoading {
                Spacer(minLength: 2)
                Text("loading…").dim()
            }
        }
    }
}

/// A line of key hints, each clickable, as in the footer.
struct KeyHints: View {
    let keys: [Footer.Key]

    var body: some View {
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

extension View {
    /// A box over the workspace, `width` columns wide with its border, and
    /// `title` in its gold top edge.
    func modal(title: String, width: Int) -> some View {
        padding(.horizontal, 1)
            .frame(width: width - 2, alignment: .topLeading)
            .background(Theme.overlay)
            .border(.rounded, color: Theme.accent)
            .overlay(alignment: .topLeading) {
                Text(" \(title) ").foregroundStyle(Theme.accent).padding(.leading, 2)
            }
    }
}
