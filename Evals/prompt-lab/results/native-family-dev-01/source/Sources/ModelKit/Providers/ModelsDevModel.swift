/// A model as models.dev describes it, reduced to what Tag Agent uses.
public struct ModelsDevModel: Sendable, Equatable, Decodable {
    /// The name to show.
    public var name: String
    /// The context window in tokens.
    public var contextLength: Int?
    /// The most tokens one reply may have.
    public var outputLimit: Int?
    /// US dollars per million input tokens.
    public var inputCost: Double?
    /// US dollars per million output tokens.
    public var outputCost: Double?
    /// Whether the model thinks before it answers.
    public var reasoning: Bool
    /// The reasoning efforts it accepts, as models.dev lists them.
    public var reasoningEfforts: [String]
    /// The assistant message field its reasoning must be sent back in
    /// (`"reasoning_content"`), when it wants it back.
    public var interleavedField: String?
    /// The AI SDK package that talks to it, when not the provider's.
    public var npm: String?
    /// Whether models.dev marks it deprecated.
    public var deprecated: Bool

    /// Creates model metadata.
    ///
    /// - Parameters:
    ///   - name: The name to show.
    ///   - contextLength: The context window.
    ///   - outputLimit: The reply token limit.
    ///   - inputCost: Dollars per million input tokens.
    ///   - outputCost: Dollars per million output tokens.
    ///   - reasoning: Whether it thinks.
    ///   - reasoningEfforts: The efforts it accepts.
    ///   - interleavedField: Where its reasoning is sent back.
    ///   - npm: Its AI SDK package.
    ///   - deprecated: Whether it is deprecated.
    public init(
        name: String,
        contextLength: Int? = nil,
        outputLimit: Int? = nil,
        inputCost: Double? = nil,
        outputCost: Double? = nil,
        reasoning: Bool = false,
        reasoningEfforts: [String] = [],
        interleavedField: String? = nil,
        npm: String? = nil,
        deprecated: Bool = false,
    ) {
        self.name = name
        self.contextLength = contextLength
        self.outputLimit = outputLimit
        self.inputCost = inputCost
        self.outputCost = outputCost
        self.reasoning = reasoning
        self.reasoningEfforts = reasoningEfforts
        self.interleavedField = interleavedField
        self.npm = npm
        self.deprecated = deprecated
    }

    /// Whether both prices are zero.
    public var isFree: Bool {
        inputCost == 0 && outputCost == 0
    }

    private enum CodingKeys: String, CodingKey {
        case name, limit, cost, reasoning, interleaved, provider, status
        case reasoningOptions = "reasoning_options"
    }

    private struct Limit: Decodable {
        var context: Int?
        var output: Int?
    }

    private struct Cost: Decodable {
        var input: Double?
        var output: Double?
    }

    private struct ReasoningOption: Decodable {
        var type: String?
        var values: [String]?
    }

    private struct Interleaved: Decodable {
        var field: String?
    }

    private struct Package: Decodable {
        var npm: String?
    }

    /// Decodes the model, tolerating missing and oddly shaped fields.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        let limit = try? container.decodeIfPresent(Limit.self, forKey: .limit)
        contextLength = limit?.context
        outputLimit = limit?.output
        let cost = try? container.decodeIfPresent(Cost.self, forKey: .cost)
        inputCost = cost?.input
        outputCost = cost?.output
        reasoning = (try? container.decodeIfPresent(Bool.self, forKey: .reasoning)) ?? false
        let options = (try? container.decodeIfPresent([Lenient<ReasoningOption>].self, forKey: .reasoningOptions)) ?? []
        reasoningEfforts = options.compactMap(\.value).first { $0.type == "effort" }?.values ?? []
        if (try? container.decodeIfPresent(Bool.self, forKey: .interleaved)) == true {
            interleavedField = "reasoning_content"
        } else {
            interleavedField = (try? container.decodeIfPresent(Interleaved.self, forKey: .interleaved))?.field
        }
        npm = (try? container.decodeIfPresent(Package.self, forKey: .provider))?.npm
        deprecated = (try? container.decodeIfPresent(String.self, forKey: .status)) == "deprecated"
    }
}
