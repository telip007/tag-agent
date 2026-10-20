/// The persisted message format uses explicit role tags, independent of
/// Swift's synthesized associated-value enum representation.
extension Message: Codable {
    private enum Keys: String, CodingKey {
        case role, text, assistant, callID, name, content
    }

    private enum Role: String, Codable {
        case system, user, assistant, tool
    }

    /// Decodes a known role, rejecting unknown roles instead of dropping history.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: Keys.self)
        switch try values.decode(Role.self, forKey: .role) {
        case .system: self = .system(try values.decode(String.self, forKey: .text))
        case .user: self = .user(try values.decode(String.self, forKey: .text))
        case .assistant: self = .assistant(try values.decode(AssistantMessage.self, forKey: .assistant))
        case .tool:
            self = .tool(
                callID: try values.decode(String.self, forKey: .callID),
                name: try values.decode(String.self, forKey: .name),
                content: try values.decode(String.self, forKey: .content))
        }
    }

    /// Encodes the role and its lossless provider-neutral payload.
    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: Keys.self)
        switch self {
        case .system(let text):
            try values.encode(Role.system, forKey: .role)
            try values.encode(text, forKey: .text)
        case .user(let text):
            try values.encode(Role.user, forKey: .role)
            try values.encode(text, forKey: .text)
        case .assistant(let message):
            try values.encode(Role.assistant, forKey: .role)
            try values.encode(message, forKey: .assistant)
        case .tool(let callID, let name, let content):
            try values.encode(Role.tool, forKey: .role)
            try values.encode(callID, forKey: .callID)
            try values.encode(name, forKey: .name)
            try values.encode(content, forKey: .content)
        }
    }
}
