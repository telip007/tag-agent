public import ModelKit

/// Complete state changes persisted before the next external operation.
public enum SessionEvent: Sendable, Equatable {
    /// Current trusted prompt, selected model and effort.
    case context(SessionContext)
    /// Exact raw and model-visible user input.
    case user(SessionUser)
    /// A request began; a crash may leave no completed reply.
    case inferenceStarted
    /// A complete assistant message and its reported usage.
    case assistant(SessionAssistant)
    /// A tool may have effects after this point.
    case toolStarted(ToolCall)
    /// A committed tool result and presentation metadata.
    case toolFinished(SessionToolResult)
    /// Explicit reversible request projection; canonical messages remain unchanged.
    case contextProjection(SessionContextProjection)
    /// A visible failure and recovery guidance.
    case failure(SessionFailure)
}

extension SessionEvent: Codable {
    private enum Keys: String, CodingKey {
        case kind, value
    }

    private enum Kind: String, Codable {
        case context, user, inferenceStarted, assistant, toolStarted, toolFinished, failure, contextProjection
    }

    /// Decodes an explicit event tag; unknown kinds fail closed.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: Keys.self)
        switch try values.decode(Kind.self, forKey: .kind) {
        case .context: self = .context(try values.decode(SessionContext.self, forKey: .value))
        case .user: self = .user(try values.decode(SessionUser.self, forKey: .value))
        case .inferenceStarted: self = .inferenceStarted
        case .assistant: self = .assistant(try values.decode(SessionAssistant.self, forKey: .value))
        case .toolStarted: self = .toolStarted(try values.decode(ToolCall.self, forKey: .value))
        case .toolFinished: self = .toolFinished(try values.decode(SessionToolResult.self, forKey: .value))
        case .contextProjection:
            let projection = try values.decode(SessionContextProjection.self, forKey: .value)
            try projection.validate()
            self = .contextProjection(projection)
        case .failure: self = .failure(try values.decode(SessionFailure.self, forKey: .value))
        }
    }

    /// Encodes stable tags, never Swift's associated-value layout.
    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: Keys.self)
        switch self {
        case .context(let value): try encode(value, kind: .context, into: &values)
        case .user(let value): try encode(value, kind: .user, into: &values)
        case .inferenceStarted: try values.encode(Kind.inferenceStarted, forKey: .kind)
        case .assistant(let value): try encode(value, kind: .assistant, into: &values)
        case .toolStarted(let value): try encode(value, kind: .toolStarted, into: &values)
        case .toolFinished(let value): try encode(value, kind: .toolFinished, into: &values)
        case .contextProjection(let value): try encode(value, kind: .contextProjection, into: &values)
        case .failure(let value): try encode(value, kind: .failure, into: &values)
        }
    }

    private func encode<Value: Encodable>(
        _ value: Value, kind: Kind, into values: inout KeyedEncodingContainer<Keys>
    ) throws {
        try values.encode(kind, forKey: .kind)
        try values.encode(value, forKey: .value)
    }
}
