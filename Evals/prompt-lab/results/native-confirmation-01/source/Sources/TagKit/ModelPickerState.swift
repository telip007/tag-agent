import ModelKit
import Observation
import Stipple

/// What the picker asks its owner to do.
enum PickerAction: Equatable {
    /// Close without changing the model.
    case close
    /// Use this model with this effort.
    case use(ModelEntry, effort: String?)
    /// Open "connect a provider".
    case connect
}

/// The model picker's state: the search, the list it gives, the highlighted
/// row and the efforts chosen. The view only draws it, so all of this is
/// tested without rendering.
///
/// The list is built again only when the search or the catalogue changes;
/// moving the highlight or changing an effort doesn't touch it.
@MainActor
@Observable
final class ModelPickerState {
    /// What the user typed.
    private(set) var query: String
    /// The list for the search.
    private(set) var rows: [PickerRow] = []
    /// The highlighted row, always a model, or `nil` when none matches.
    private(set) var highlighted: Int?
    /// The first row in view.
    private(set) var windowStart = 0
    /// Whether the catalogue is still loading.
    private(set) var isLoading: Bool
    /// The efforts chosen while the picker is open, by model.
    private(set) var efforts: [ModelRef: String] = [:]
    /// Why the last model chosen couldn't be used.
    var error: String?
    /// How many rows the view shows; set by the owner from the terminal size.
    @ObservationIgnored var rowLimit = 12

    /// The model in use, marked in the list.
    let current: ModelRef?
    @ObservationIgnored private let recent: [ModelRef]
    @ObservationIgnored private let rememberedEffort: (ModelEntry) -> String?
    @ObservationIgnored private var models: [SearchableModel] = []
    @ObservationIgnored private var failures: [ProviderID: String] = [:]

    /// Creates a picker.
    ///
    /// - Parameters:
    ///   - query: The search to start with.
    ///   - catalogue: The models to pick from; `nil` while loading.
    ///   - current: The model in use.
    ///   - recent: Recently used models, newest first.
    ///   - effort: The effort to offer a model at first.
    init(
        query: String = "",
        catalogue: Catalogue?,
        current: ModelRef?,
        recent: [ModelRef],
        effort: @escaping (ModelEntry) -> String?,
    ) {
        self.query = query
        self.current = current
        self.recent = recent
        self.rememberedEffort = effort
        isLoading = catalogue == nil
        if let catalogue {
            update(catalogue: catalogue)
        }
    }

    /// Lists `catalogue`'s models, keeping the highlighted model when it's still there.
    func update(catalogue: Catalogue) {
        let kept = highlightedEntry?.ref
        models = catalogue.entries.map(SearchableModel.init)
        failures = catalogue.failures
        isLoading = false
        rebuild(keeping: kept)
    }

    /// The highlighted model.
    var highlightedEntry: ModelEntry? {
        highlighted.flatMap { rows[$0].entry }
    }

    /// The effort `entry` would be used with.
    func effort(for entry: ModelEntry) -> String? {
        efforts[entry.ref] ?? rememberedEffort(entry)
    }

    /// Whether no provider has listed any model.
    var hasNoModels: Bool {
        models.isEmpty
    }

    /// Adds `text` to the search.
    func type(_ text: String) {
        setQuery(query + text.filter { $0 != "\n" && $0 != "\r" })
    }

    /// Removes the last character of the search.
    func deleteBackward() {
        setQuery(String(query.dropLast()))
    }

    /// Removes the last word of the search.
    func deleteWord() {
        var text = Substring(query)
        while text.last?.isWhitespace == true {
            text.removeLast()
        }
        while let last = text.last, !last.isWhitespace {
            text.removeLast()
        }
        setQuery(String(text))
    }

    /// Replaces the search.
    func setQuery(_ text: String) {
        guard text != query else {
            return
        }
        query = text
        error = nil
        rebuild(keeping: nil)
    }

    /// Highlights the model `offset` model rows away, stopping at the ends.
    func move(by offset: Int) {
        let models = rows.indices.filter { rows[$0].entry != nil }
        guard !models.isEmpty else {
            return
        }
        let position = highlighted.flatMap(models.firstIndex(of:)) ?? 0
        highlight(models[min(max(position + offset, 0), models.count - 1)])
    }

    /// Highlights row `index` when it's a model, and scrolls it into view.
    func highlight(_ index: Int) {
        guard rows.indices.contains(index), rows[index].entry != nil else {
            return
        }
        highlighted = index
        // A section's first model brings its title into view too.
        let top = index > 0 && rows[index - 1].entry == nil ? index - 1 : index
        windowStart = min(windowStart, top)
        windowStart = max(windowStart, index - rowLimit + 1)
        windowStart = max(0, min(windowStart, max(rows.count - rowLimit, 0)))
    }

    /// Steps the highlighted model's effort by `offset`, wrapping around.
    func cycleEffort(by offset: Int) {
        guard let entry = highlightedEntry, !entry.reasoningEfforts.isEmpty else {
            return
        }
        let efforts = entry.reasoningEfforts
        let position = effort(for: entry).flatMap(efforts.firstIndex(of:)) ?? 0
        self.efforts[entry.ref] = efforts[(position + offset % efforts.count + efforts.count) % efforts.count]
    }

    /// The rows in view for a window of `limit` rows.
    func window(limit: Int) -> Range<Int> {
        let limit = max(limit, 1)
        let start = max(0, min(windowStart, rows.count - limit))
        return start..<min(rows.count, start + limit)
    }

    private func rebuild(keeping kept: ModelRef?) {
        rows = PickerList.rows(models: models, query: query, recent: recent, failures: failures)
        windowStart = 0
        highlighted = nil
        let preferred = kept ?? (query.isEmpty ? current : nil)
        let index = preferred.flatMap { ref in rows.firstIndex { $0.entry?.ref == ref } }
        if let index = index ?? rows.firstIndex(where: { $0.entry != nil }) {
            highlight(index)
        }
    }
}

extension ModelPickerState {
    /// Acts on a key press: typing searches, ↑↓ move, ←→ change the effort,
    /// Enter uses the model, Esc closes, Ctrl-A connects a provider.
    ///
    /// - Returns: What the owner should do, or `nil`; `handled` says
    ///   whether the press was the picker's.
    func handle(_ press: KeyPress) -> (handled: Bool, action: PickerAction?) {
        guard let key = PickerKey(press) else {
            return (false, nil)
        }
        switch key {
        case .type(let text): type(text)
        case .deleteBackward: deleteBackward()
        case .deleteWord: deleteWord()
        case .clear: setQuery("")
        case .move(let offset): move(by: offset == .max ? rowLimit : offset == .min ? -rowLimit : offset)
        case .effort(let offset): cycleEffort(by: offset)
        case .close: return (true, .close)
        case .connect: return (true, .connect)
        case .use:
            guard let entry = highlightedEntry else {
                return (true, nil)
            }
            return (true, .use(entry, effort: effort(for: entry)))
        }
        return (true, nil)
    }
}

/// What a key press means in the picker.
enum PickerKey: Equatable {
    case type(String)
    case deleteBackward
    case deleteWord
    case clear
    /// Move the highlight; `Int.max` and `Int.min` are a page down and up.
    case move(Int)
    case effort(Int)
    case use
    case close
    case connect

    init?(_ press: KeyPress) {
        guard press.phase != .up else {
            return nil
        }
        let modifiers = press.modifiers.subtracting([.capsLock, .numLock, .shift])
        switch (press.key, modifiers) {
        case (.upArrow, []), ("p", .control): self = .move(-1)
        case (.downArrow, []), ("n", .control): self = .move(1)
        case (.pageUp, []): self = .move(.min)
        case (.pageDown, []): self = .move(.max)
        case (.leftArrow, []): self = .effort(-1)
        case (.rightArrow, []): self = .effort(1)
        case (.return, []): self = .use
        case (.escape, []): self = .close
        case ("a", .control): self = .connect
        case ("u", .control): self = .clear
        case ("w", .control), (.backspace, .option), (.backspace, .control): self = .deleteWord
        case (.backspace, []): self = .deleteBackward
        default:
            guard let text = press.typedText else {
                return nil
            }
            self = .type(text)
        }
    }
}
