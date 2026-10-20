/// Walks back and forth through sent messages with the arrow keys, as a
/// shell does: the first ↑ remembers the line being typed, and ↓ past the
/// newest message brings it back.
struct InputHistory: Equatable {
    /// Which message is shown, or `nil` while editing a fresh line.
    private(set) var index: Int?
    /// The line that was being typed before the first ↑.
    private var draft = ""

    /// The text to show after ↑, or `nil` when there is nothing older.
    mutating func older(in history: [String], current: String) -> String? {
        guard !history.isEmpty else {
            return nil
        }
        guard let index else {
            draft = current
            self.index = history.count - 1
            return history[history.count - 1]
        }
        guard index > 0 else {
            return nil
        }
        self.index = index - 1
        return history[index - 1]
    }

    /// The text to show after ↓, or `nil` when already on a fresh line.
    mutating func newer(in history: [String]) -> String? {
        guard let index else {
            return nil
        }
        guard index + 1 < history.count else {
            self.index = nil
            return draft
        }
        self.index = index + 1
        return history[index + 1]
    }

    /// Forgets the position, e.g. after sending.
    mutating func reset() {
        index = nil
        draft = ""
    }
}
