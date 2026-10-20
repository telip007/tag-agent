import Foundation

/// Budgets complete UTF-8 text without manufacturing replacement characters.
enum ContextText {
    static func prefix(_ text: String, bytes: Int) -> String {
        var data = Data(text.utf8.prefix(max(0, bytes)))
        while !data.isEmpty, String(validating: data, as: UTF8.self) == nil { data.removeLast() }
        return String(validating: data, as: UTF8.self) ?? ""
    }

    static func suffix(_ text: String, bytes: Int) -> String {
        var data = Data(text.utf8.suffix(max(0, bytes)))
        while let first = data.first, first & 0xC0 == 0x80 { data.removeFirst() }
        return String(validating: data, as: UTF8.self) ?? ""
    }

    static func json(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let text = String(bytes: try encoder.encode(value), encoding: .utf8) else {
            throw ToolError("Context output could not be encoded as UTF-8.")
        }
        return text
    }
}
