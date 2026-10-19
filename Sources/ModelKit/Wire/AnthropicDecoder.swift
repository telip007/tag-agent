import OpenRouter

/// Decodes Anthropic Messages events: content blocks (text, thinking with
/// its signature, tool use with streamed input JSON) and usage. A reply
/// with thinking keeps its blocks verbatim to replay on the next turn.
struct AnthropicDecoder: WireDecoder {
    private struct Block {
        var start: [String: JSONValue]
        var text = ""
        var signature = ""
        var inputJSON = ""

        var type: String { start["type"]?.stringValue ?? "" }

        /// The block as the API would send it whole.
        var json: JSONValue {
            var block = start
            switch type {
            case "text": block["text"] = .string(text)
            case "thinking":
                block["thinking"] = .string(text)
                block["signature"] = .string(signature)
            case "tool_use": block["input"] = input
            default: break
            }
            return .object(block)
        }

        var input: JSONValue {
            if let input = JSONValue.parse(inputJSON), input.objectValue != nil {
                return input
            }
            return start["input"] ?? [:]
        }
    }

    private let provider: ProviderID
    private var blocks: [Int: Block] = [:]
    private var order: [Int] = []
    private var inputTokens = 0
    private var outputTokens = 0
    private var started = false

    init(provider: ProviderID) {
        self.provider = provider
    }

    mutating func decode(_ event: ServerSentEvent) throws -> [ReplyDelta] {
        // OpenAI-style gateways (OpenRouter among them) end every stream with
        // `data: [DONE]`, also in this format.
        guard event.data != "[DONE]" else {
            return []
        }
        guard let data = JSONValue.parse(event.data) else {
            throw ProviderError.malformedResponse(provider, detail: "An event wasn't JSON.")
        }
        switch data["type"]?.stringValue ?? event.event {
        case "message_start":
            started = true
            addUsage(data["message"]?["usage"])
        case "content_block_start":
            return start(data)
        case "content_block_delta":
            return delta(data)
        case "message_delta":
            addUsage(data["usage"])
        case "error":
            throw ProviderError.streamed(data["error"] ?? data, provider: provider)
        default:
            break
        }
        return []
    }

    private mutating func addUsage(_ usage: JSONValue?) {
        guard let usage else {
            return
        }
        let input = ["input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens"]
            .compactMap { usage[$0]?.intValue }
        if !input.isEmpty, input.reduce(0, +) > 0 {
            inputTokens = input.reduce(0, +)
        }
        if let output = usage["output_tokens"]?.intValue {
            outputTokens = output
        }
    }

    private mutating func start(_ data: JSONValue) -> [ReplyDelta] {
        guard let index = data["index"]?.intValue, let start = data["content_block"]?.objectValue else {
            return []
        }
        var block = Block(start: start)
        block.text = start["text"]?.stringValue ?? start["thinking"]?.stringValue ?? ""
        block.signature = start["signature"]?.stringValue ?? ""
        blocks[index] = block
        order.append(index)
        switch block.type {
        case "tool_use": return [.toolCall(name: start["name"]?.stringValue ?? "")]
        case "text" where !block.text.isEmpty: return [.text(block.text)]
        case "thinking" where !block.text.isEmpty: return [.reasoning(block.text)]
        default: return []
        }
    }

    private mutating func delta(_ data: JSONValue) -> [ReplyDelta] {
        guard let index = data["index"]?.intValue, var block = blocks[index], let delta = data["delta"] else {
            return []
        }
        defer { blocks[index] = block }
        switch delta["type"]?.stringValue {
        case "text_delta":
            let text = delta["text"]?.stringValue ?? ""
            block.text += text
            return text.isEmpty ? [] : [.text(text)]
        case "thinking_delta":
            let thinking = delta["thinking"]?.stringValue ?? ""
            block.text += thinking
            return thinking.isEmpty ? [] : [.reasoning(thinking)]
        case "signature_delta":
            block.signature += delta["signature"]?.stringValue ?? ""
        case "input_json_delta":
            block.inputJSON += delta["partial_json"]?.stringValue ?? ""
        default:
            break
        }
        return []
    }

    func reply() throws -> ModelReply {
        guard started else {
            throw ProviderError.malformedResponse(provider, detail: "The stream ended without a reply.")
        }
        let ordered = order.compactMap { blocks[$0] }
        let text = ordered.filter { $0.type == "text" }.map(\.text).joined()
        let reasoning = ordered.filter { $0.type == "thinking" }.map(\.text).joined()
        let toolCalls = ordered.filter { $0.type == "tool_use" }.map { block in
            ToolCall(
                id: block.start["id"]?.stringValue ?? "", name: block.start["name"]?.stringValue ?? "",
                arguments: block.input.jsonText)
        }
        let thinks = ordered.contains { $0.type == "thinking" || $0.type == "redacted_thinking" }
        let replay = thinks ? [ReplayItem(format: .anthropicMessages, payload: .array(ordered.map(\.json)))] : []
        let message = AssistantMessage(
            text: text.isEmpty ? nil : text, reasoning: reasoning.isEmpty ? nil : reasoning, replay: replay,
            toolCalls: toolCalls)
        return ModelReply(message: message, usage: Usage(inputTokens: inputTokens, outputTokens: outputTokens))
    }
}
