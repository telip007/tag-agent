import Foundation
import OpenRouter

/// Reading and writing the loosely typed JSON the wire formats stream.
extension JSONValue {
    /// The member `key` of an object; `nil` for other values.
    subscript(key: String) -> Self? {
        objectValue?[key]
    }

    /// The value as a string.
    var stringValue: String? {
        if case .string(let value) = self {
            return value
        }
        return nil
    }

    /// The value as an integer; whole doubles count.
    var intValue: Int? {
        switch self {
        case .int(let value): value
        case .double(let value): Int(exactly: value)
        default: nil
        }
    }

    /// The value as a number.
    var doubleValue: Double? {
        switch self {
        case .int(let value): Double(value)
        case .double(let value): value
        default: nil
        }
    }

    /// The value as a boolean.
    var boolValue: Bool? {
        if case .bool(let value) = self {
            return value
        }
        return nil
    }

    /// The value as an array.
    var arrayValue: [Self]? {
        if case .array(let value) = self {
            return value
        }
        return nil
    }

    /// The value as an object.
    var objectValue: [String: Self]? {
        if case .object(let value) = self {
            return value
        }
        return nil
    }

    /// Parses JSON text; `nil` when it isn't JSON.
    static func parse(_ text: String) -> Self? {
        parse(Data(text.utf8))
    }

    /// Parses JSON data; `nil` when it isn't JSON.
    static func parse(_ data: Data) -> Self? {
        try? JSONDecoder().decode(Self.self, from: data)
    }

    /// The value as compact JSON text, keys sorted.
    var jsonText: String {
        (try? Self.encoder.encode(self)).flatMap { String(bytes: $0, encoding: .utf8) } ?? "null"
    }

    /// The value as JSON data.
    func encoded() throws -> Data {
        try Self.encoder.encode(self)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
