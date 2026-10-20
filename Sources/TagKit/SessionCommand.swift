import Foundation

/// Explicit local commands are intercepted before model input is accepted.
enum SessionCommand: Equatable {
    case browse
    case new
    case resume(String)
    case rename(String)
    case reference(String?, String)
    case unreference
    case pending
    case retry
    case invalid(String)

    init?(_ input: String) {
        let input = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = input.split(maxSplits: 1, whereSeparator: \.isWhitespace).map(String.init)
        guard let command = parts.first else { return nil }
        let argument = parts.count == 2 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
        switch command {
        case "/sessions": self = argument.isEmpty ? .browse : .invalid("Usage: /sessions")
        case "/new", "/clear": self = argument.isEmpty ? .new : .invalid("Usage: \(command)")
        case "/session": self = argument.isEmpty ? .invalid("Usage: /session <id>") : .resume(argument)
        case "/rename": self = argument.isEmpty ? .invalid("Usage: /rename <title>") : .rename(argument)
        case "/reference":
            let source = argument.split(maxSplits: 1, whereSeparator: \.isWhitespace).map(String.init)
            self = .reference(source.first, source.count == 2 ? source[1] : "")
        case "/unreference": self = argument.isEmpty ? .unreference : .invalid("Usage: /unreference")
        case "/pending": self = argument.isEmpty ? .pending : .invalid("Usage: /pending")
        case "/retry": self = argument.isEmpty ? .retry : .invalid("Usage: /retry")
        default: return nil
        }
    }
}
