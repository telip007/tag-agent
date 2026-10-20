import Foundation

/// The gist of a tool call's JSON arguments, for one line in the transcript:
/// `swift build` rather than `{"command":"swift build"}`.
enum ToolSummary {
    /// Arguments that say most about a call, in order of preference.
    static let keyArguments = ["command", "path", "pattern"]
    /// Longer summaries are cut with `…`.
    static let maxLength = 60

    /// The most telling argument's value on one line, or the raw arguments
    /// when they aren't a JSON object with a string value.
    static func summarize(_ arguments: String) -> String {
        let object = (try? JSONSerialization.jsonObject(with: Data(arguments.utf8))) as? [String: Any]
        guard let object else {
            return truncated(oneLine(arguments))
        }
        let preferred = keyArguments.lazy.compactMap { object[$0] as? String }.first
        let anyString = object.keys.sorted().lazy.compactMap { object[$0] as? String }.first
        return truncated(oneLine(preferred ?? anyString ?? ""))
    }

    private static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).joined(separator: " ⏎ ")
    }

    private static func truncated(_ text: String) -> String {
        text.count > maxLength ? text.prefix(maxLength - 1) + "…" : text
    }
}
