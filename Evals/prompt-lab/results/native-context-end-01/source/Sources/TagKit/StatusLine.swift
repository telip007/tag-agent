public import Foundation
public import ModelKit

/// The single line printed above the prompt: where the agent is working,
/// which model is answering, how full the context is and what the session
/// has cost.
public struct StatusLine: Sendable, Equatable {
    /// The directory the agent was started in.
    public var directory: URL
    /// The model answering, with its display name and context window.
    public var model: ModelDescription
    /// Tokens the context holds after the latest reply. Zero before any reply.
    public var contextTokens: Int
    /// Total cost of the session, in US dollars.
    public var cost: Double

    /// Usage of the latest request, including optional cache counts.
    public var usage: Usage?

    /// Cache reads and writes when the provider reports them.
    public var cacheUsage: String? {
        var parts: [String] = []
        if let read = usage?.cachedInputTokens {
            parts.append("read \(Self.tokens(read))")
        }
        if let written = usage?.cacheWriteInputTokens {
            parts.append("write \(Self.tokens(written))")
        }
        return parts.isEmpty ? nil : "cache " + parts.joined(separator: " · ")
    }

    /// Creates a status line.
    ///
    /// - Parameters:
    ///   - directory: The directory the agent was started in.
    ///   - model: The model answering.
    ///   - contextTokens: Tokens in the context after the latest reply.
    ///   - cost: Total cost of the session in US dollars.
    ///   - usage: Usage of the latest request.
    public init(directory: URL, model: ModelDescription, contextTokens: Int = 0, cost: Double = 0, usage: Usage? = nil)
    {
        self.directory = directory
        self.model = model
        self.contextTokens = contextTokens
        self.cost = cost
        self.usage = usage
    }

    /// The rendered line, with fields separated by `·`.
    public var text: String {
        [folder, model.name, context, cacheUsage, money].compactMap { $0 }.joined(separator: " · ")
    }

    /// The working directory, with the home directory shortened to `~`.
    public var folder: String {
        Self.folder(directory)
    }

    /// The session cost: `$0.00`, `$0.0012`, `$1.50`.
    public var money: String {
        Self.money(cost)
    }

    /// How full the context window is, from 0 to 1 (more if it overflowed),
    /// or `nil` when the catalogue doesn't know the window.
    public var contextFraction: Double? {
        guard let length = model.contextLength, length > 0 else {
            return nil
        }
        return Double(contextTokens) / Double(length)
    }

    /// `ctx 1.2k/64k (2%)`, or `ctx 1.2k` when the catalogue doesn't know the window.
    public var context: String {
        guard let fraction = contextFraction else {
            return "ctx \(contextUsage)"
        }
        let percent = Int((fraction * 100).rounded())
        return "ctx \(contextUsage) (\(percent)%)"
    }

    /// `1.2k/64k`, or `1.2k` when the catalogue doesn't know the window.
    public var contextUsage: String {
        let used = Self.tokens(contextTokens)
        guard let length = model.contextLength, length > 0 else {
            return used
        }
        return "\(used)/\(Self.tokens(length))"
    }

    /// The path with the home directory shortened to `~`.
    static func folder(_ directory: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String {
        let path = normalized(directory)
        let homePath = normalized(home)
        if path == homePath {
            return "~"
        }
        guard path.hasPrefix(homePath + "/") else {
            return path
        }
        return "~" + path.dropFirst(homePath.count)
    }

    /// A URL's path, without the trailing slash `.isDirectory` URLs carry.
    private static func normalized(_ url: URL) -> String {
        let path = url.path(percentEncoded: false)
        guard path.count > 1, path.hasSuffix("/") else {
            return path
        }
        return String(path.dropLast())
    }

    /// `999`, `1.2k`, `64k`, `1.5M`.
    static func tokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return scaled(count, by: 1_000_000, suffix: "M")
        }
        if count >= 1_000 {
            return scaled(count, by: 1_000, suffix: "k")
        }
        return "\(count)"
    }

    /// Rounds to one decimal: `1.2k`, but `64k` rather than `64.0k`.
    private static func scaled(_ count: Int, by unit: Int, suffix: String) -> String {
        let tenths = (count * 10 + unit / 2) / unit
        let whole = tenths / 10
        let fraction = tenths % 10
        return fraction == 0 ? "\(whole)\(suffix)" : "\(whole).\(fraction)\(suffix)"
    }

    /// `$1.50`, `$0.0012`, `$0.000123` — enough decimals to show the amount.
    static func money(_ cost: Double) -> String {
        guard cost > 0 else {
            return "$0.00"
        }
        let digits = cost < 0.01 ? 6 : 4
        let scale = digits == 6 ? 1_000_000 : 10_000
        let scaled = Int((cost * Double(scale)).rounded())
        let remainder = "\(scaled % scale)"
        let fraction = String(repeating: "0", count: max(0, digits - remainder.count)) + remainder
        return "$\(scaled / scale)." + trimmed(fraction)
    }

    /// Drops trailing zeros, keeping at least two decimals.
    private static func trimmed(_ digits: String) -> String {
        var digits = digits
        while digits.count > 2, digits.hasSuffix("0") {
            digits.removeLast()
        }
        return digits
    }
}
