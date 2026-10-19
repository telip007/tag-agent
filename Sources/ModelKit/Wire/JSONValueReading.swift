import OpenRouter

/// Reading parts of a decoded JSON value without a `Codable` type, for
/// responses whose shape is only partly known.
extension JSONValue {
    /// The member `key` of an object; `nil` for other values.
    func member(_ key: String) -> Self? {
        guard case .object(let object) = self else {
            return nil
        }
        return object[key]
    }

    /// The value of a string.
    var string: String? {
        guard case .string(let value) = self else {
            return nil
        }
        return value
    }

    /// The value of a whole number, also when written as a double.
    var int: Int? {
        switch self {
        case .int(let value): value
        case .double(let value): Int(exactly: value)
        default: nil
        }
    }

    /// The elements of an array.
    var array: [Self]? {
        guard case .array(let value) = self else {
            return nil
        }
        return value
    }
}
