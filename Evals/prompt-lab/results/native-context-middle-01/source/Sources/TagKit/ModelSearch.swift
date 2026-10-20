import Foundation
import ModelKit

/// A catalogue entry as the picker searches it: its words and text,
/// lowercased once when the catalogue loads, so a key press only compares.
struct SearchableModel {
    let entry: ModelEntry
    /// The words of the name, the model id, and the provider's name and aliases.
    let words: [String]
    /// The name, the model id and the provider's name, for substring and
    /// subsequence matches.
    let text: String
    /// The name and the model id as one search's words would spell them,
    /// so a search for the whole name ranks that model first.
    let phrases: [String]

    init(_ entry: ModelEntry) {
        self.entry = entry
        let provider = entry.ref.provider
        let sources = [entry.name, entry.ref.model, provider.displayName] + provider.aliases
        words = sources.flatMap(Self.words(in:))
        text = "\(entry.name) \(entry.ref.model) \(provider.displayName)".lowercased()
        phrases = [entry.name, entry.ref.model].map { Self.tokens(of: $0).joined(separator: " ") }
    }

    /// How well the model matches every token of a search, or `nil` when one
    /// doesn't match. A word starting with the token counts most, then the
    /// token anywhere in the text, then its letters in order. A search that
    /// spells the whole name or id counts extra.
    func score(_ tokens: [String]) -> Int? {
        let phrase = tokens.joined(separator: " ")
        var total = phrases.contains(phrase) ? 6 : 0
        for token in tokens {
            if words.contains(where: { $0.hasPrefix(token) }) {
                total += 3
            } else if text.contains(token) {
                total += 2
            } else if Self.isSubsequence(token, of: text) {
                total += 1
            } else {
                return nil
            }
        }
        return total
    }

    /// The lowercased words of `text`, split at anything but letters and digits.
    static func words(in text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    /// The tokens of a search: its words, lowercased. A `/` separates words
    /// too, so `go/kimi` finds Kimi on OpenCode Go.
    static func tokens(of query: String) -> [String] {
        query.lowercased().split { $0.isWhitespace || $0 == "/" }.map(String.init)
    }

    /// Whether `needle`'s characters appear in `haystack` in order.
    static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var remaining = needle.unicodeScalars.makeIterator()
        var next = remaining.next()
        for scalar in haystack.unicodeScalars where scalar == next {
            next = remaining.next()
            if next == nil {
                return true
            }
        }
        return next == nil
    }
}

/// One line of the picker's list.
enum PickerRow: Equatable {
    /// A section title: `recent`, or a provider.
    case header(String)
    /// A model; in the recent section it names its provider instead of its context.
    case model(ModelEntry, isRecent: Bool)
    /// A provider whose catalogue couldn't be read.
    case failure(ProviderID, String)

    /// The model, if the row is one.
    var entry: ModelEntry? {
        if case .model(let entry, _) = self { entry } else { nil }
    }
}

/// Builds the picker's list: recent models first, then every model grouped
/// by provider. A search keeps the models matching each of its words, and
/// puts the best matches first within each section and the best provider first.
enum PickerList {
    static func rows(
        models: [SearchableModel],
        query: String,
        recent: [ModelRef],
        failures: [ProviderID: String],
    ) -> [PickerRow] {
        let tokens = SearchableModel.tokens(of: query)
        var matches: [(model: SearchableModel, score: Int)] = []
        for model in models {
            if let score = model.score(tokens) {
                matches.append((model, score))
            }
        }
        var rows: [PickerRow] = []
        if tokens.isEmpty {
            rows += failures.sorted { $0.key < $1.key }.map { PickerRow.failure($0.key, $0.value) }
        }
        let recentMatches = recent.compactMap { ref in matches.first { $0.model.entry.ref == ref } }
        if !recentMatches.isEmpty {
            rows.append(.header("recent"))
            rows += recentMatches.map { .model($0.model.entry, isRecent: true) }
        }
        for group in groups(of: matches, ranked: !tokens.isEmpty) {
            rows.append(.header(label(group.provider)))
            rows += group.entries.map { .model($0, isRecent: false) }
        }
        return rows
    }

    /// A model that matched, with its score and its place in the catalogue.
    private struct Match {
        let entry: ModelEntry
        let score: Int
        let index: Int
    }

    /// The matches by provider, in catalogue order; ranked, the best matches
    /// lead (stable, so equal scores keep the catalogue's order).
    private static func groups(
        of matches: [(model: SearchableModel, score: Int)],
        ranked: Bool,
    ) -> [(provider: ProviderID, entries: [ModelEntry])] {
        var order: [ProviderID] = []
        var byProvider: [ProviderID: [Match]] = [:]
        for (index, match) in matches.enumerated() {
            let provider = match.model.entry.ref.provider
            if byProvider[provider] == nil {
                order.append(provider)
            }
            byProvider[provider, default: []].append(Match(entry: match.model.entry, score: match.score, index: index))
        }
        guard ranked else {
            return order.map { ($0, byProvider[$0]?.map(\.entry) ?? []) }
        }
        let ranking = { (lhs: Match, rhs: Match) in
            lhs.score != rhs.score ? lhs.score > rhs.score : lhs.index < rhs.index
        }
        let groups = order.compactMap { provider in byProvider[provider]?.sorted(by: ranking) }
        return groups.sorted { lhs, rhs in
            guard let left = lhs.first, let right = rhs.first else {
                return false
            }
            return ranking(left, right)
        }
        .compactMap { group in group.first.map { ($0.entry.ref.provider, group.map(\.entry)) } }
    }

    /// A provider as the list names it: `openrouter`, `opencode go`.
    static func label(_ provider: ProviderID) -> String {
        provider.displayName.lowercased()
    }

    /// `400k ctx`, or nothing when the window isn't known.
    static func context(_ entry: ModelEntry) -> String {
        entry.contextLength.map { "\(StatusLine.tokens($0)) ctx" } ?? ""
    }

    /// `included`, `free`, `$1.25 / $10`, or nothing when not known.
    static func price(_ pricing: Pricing) -> String {
        switch pricing {
        case .included: "included"
        case .free: "free"
        case .perMillion(let input, let output): "$\(dollars(input)) / $\(dollars(output))"
        case .unknown: ""
        }
    }

    /// `10`, `1.25`, `0.075`: up to three decimals, without trailing zeros.
    static func dollars(_ value: Double) -> String {
        let thousandths = Int((value * 1_000).rounded())
        let whole = thousandths / 1_000
        var fraction = String(thousandths % 1_000)
        fraction = String(repeating: "0", count: 3 - fraction.count) + fraction
        while fraction.hasSuffix("0") {
            fraction.removeLast()
        }
        return fraction.isEmpty ? "\(whole)" : "\(whole).\(fraction)"
    }
}
