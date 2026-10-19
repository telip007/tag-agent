import Foundation
import OpenRouter

/// Decodes Gemini `streamGenerateContent` chunks: text and thought parts,
/// function calls, thought signatures (kept to replay the parts verbatim on
/// the next turn) and usage.
struct GeminiDecoder: WireDecoder {
    private struct Part {
        var thought = false
        var text = ""
        var call: JSONValue?
        var signature: String?

        var json: JSONValue {
            var part: [String: JSONValue] = [:]
            if let call {
                part["functionCall"] = call
            } else {
                part["text"] = .string(text)
                if thought {
                    part["thought"] = true
                }
            }
            if let signature {
                part["thoughtSignature"] = .string(signature)
            }
            return .object(part)
        }
    }

    private let provider: ProviderID
    private var parts: [Part] = []
    private var toolCalls: [ToolCall] = []
    private var usage: Usage?
    private var sawChunk = false

    init(provider: ProviderID) {
        self.provider = provider
    }

    mutating func decode(_ event: ServerSentEvent) throws -> [ReplyDelta] {
        guard let chunk = JSONValue.parse(event.data) else {
            throw ProviderError.malformedResponse(provider, detail: "A stream chunk wasn't JSON.")
        }
        if let error = chunk["error"] {
            throw ProviderError.streamed(error, provider: provider)
        }
        sawChunk = true
        if let metadata = chunk["usageMetadata"] {
            usage = Usage(
                inputTokens: metadata["promptTokenCount"]?.intValue ?? 0,
                outputTokens: (metadata["candidatesTokenCount"]?.intValue ?? 0)
                    + (metadata["thoughtsTokenCount"]?.intValue ?? 0))
        }
        let content = chunk["candidates"]?.arrayValue?.first?["content"]?["parts"]?.arrayValue ?? []
        return content.flatMap { add($0) }
    }

    private mutating func add(_ json: JSONValue) -> [ReplyDelta] {
        let signature = json["thoughtSignature"]?.stringValue
        if let call = json["functionCall"] {
            let name = call["name"]?.stringValue ?? ""
            let id = call["id"]?.stringValue ?? "call_\(UUID().uuidString.prefix(8).lowercased())"
            toolCalls.append(ToolCall(id: id, name: name, arguments: (call["args"] ?? [:]).jsonText))
            parts.append(Part(call: call, signature: signature))
            return [.toolCall(name: name)]
        }
        guard let text = json["text"]?.stringValue else {
            return []
        }
        let thought = json["thought"]?.boolValue ?? false
        if let last = parts.last, last.call == nil, last.thought == thought, signature == nil || last.signature == nil {
            parts[parts.count - 1].text += text
            parts[parts.count - 1].signature = last.signature ?? signature
        } else {
            parts.append(Part(thought: thought, text: text, signature: signature))
        }
        guard !text.isEmpty else {
            return []
        }
        return [thought ? .reasoning(text) : .text(text)]
    }

    func reply() throws -> ModelReply {
        guard sawChunk else {
            throw ProviderError.malformedResponse(provider, detail: "The stream ended without a reply.")
        }
        let text = parts.filter { $0.call == nil && !$0.thought }.map(\.text).joined()
        let reasoning = parts.filter(\.thought).map(\.text).joined()
        let signed = parts.contains { $0.signature != nil }
        let replay = signed ? [ReplayItem(format: .gemini, payload: .array(parts.map(\.json)))] : []
        let message = AssistantMessage(
            text: text.isEmpty ? nil : text, reasoning: reasoning.isEmpty ? nil : reasoning, replay: replay,
            toolCalls: toolCalls)
        return ModelReply(message: message, usage: usage)
    }
}
