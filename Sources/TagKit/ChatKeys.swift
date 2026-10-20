import Stipple

/// What a key press means at the prompt, beyond editing the line.
enum PromptKey: Equatable {
    /// Ctrl-C.
    case interrupt
    /// Ctrl-D on an empty line, as end-of-file in a shell.
    case endOfInput
    /// ↑: an older message from the history.
    case older
    /// ↓: a newer message, or back to the line being typed.
    case newer
    /// Esc on an empty line: browse past blocks.
    case browse
    /// Ctrl-P: the command palette.
    case palette
    /// Ctrl-O: search saved conversations.
    case sessions
    /// Tab: show or hide the session panel.
    case togglePanel

    init?(_ press: KeyPress, inputIsEmpty: Bool) {
        guard press.phase != .up else {
            return nil
        }
        switch (press.key, press.modifiers.subtracting([.capsLock, .numLock])) {
        case ("c", .control):
            self = .interrupt
        case ("d", .control) where inputIsEmpty:
            self = .endOfInput
        case ("o", .control):
            self = .sessions
        case ("p", .control):
            self = .palette
        case (.upArrow, []):
            self = .older
        case (.downArrow, []):
            self = .newer
        case (.escape, []) where inputIsEmpty:
            self = .browse
        case (.tab, []):
            self = .togglePanel
        default:
            return nil
        }
    }
}

/// What a key press means while browsing past blocks.
enum BrowseKey: Equatable {
    case previous
    case next
    case toggle
    case copy
    /// Back to the input line; a typed character goes into it.
    case leave

    init?(_ press: KeyPress) {
        guard press.phase != .up else {
            return nil
        }
        switch (press.key, press.modifiers.subtracting([.capsLock, .numLock])) {
        case (.upArrow, []), ("k", []):
            self = .previous
        case (.downArrow, []), ("j", []):
            self = .next
        case (.return, []), (.space, []):
            self = .toggle
        case ("c", []), ("y", []):
            self = .copy
        case (.escape, _), (.character, _):
            self = .leave
        default:
            return nil
        }
    }
}

extension KeyPress {
    /// The text a press types, if it types any: a plain character without
    /// Control, Option or Command.
    var typedText: String? {
        guard case .character(let character) = key,
            modifiers.isDisjoint(with: [.control, .option, .command])
        else {
            return nil
        }
        return characters.isEmpty ? String(character) : characters
    }
}
