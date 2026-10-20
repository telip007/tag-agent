public import ModelKit

/// The model the agent talks to right now: the catalogue entry, the chat
/// model built for it, and the reasoning effort chosen.
public struct ActiveModel {
    /// The model as the catalogue lists it.
    public var entry: ModelEntry
    /// What writes the replies.
    public var chatModel: any ChatModel
    /// How hard the model should think, or `nil` for its default.
    public var effort: String?

    /// Creates an active model.
    ///
    /// - Parameters:
    ///   - entry: The model as the catalogue lists it.
    ///   - chatModel: What writes the replies.
    ///   - effort: The reasoning effort, or `nil` for the model's default.
    public init(entry: ModelEntry, chatModel: any ChatModel, effort: String? = nil) {
        self.entry = entry
        self.chatModel = chatModel
        self.effort = effort
    }

    /// The name and context window for the status line.
    public var description: ModelDescription {
        ModelDescription(name: entry.name, contextLength: entry.contextLength)
    }
}

/// A human-readable description of a model, shown in the status line.
public struct ModelDescription: Sendable, Equatable {
    /// The name to show, e.g. `"DeepSeek V4.1 Flash"`.
    public var name: String
    /// The model's context window in tokens, when the catalogue reports it.
    public var contextLength: Int?

    /// Creates a model description.
    ///
    /// - Parameters:
    ///   - name: The name to show.
    ///   - contextLength: The context window in tokens, when known.
    public init(name: String, contextLength: Int? = nil) {
        self.name = name
        self.contextLength = contextLength
    }
}
