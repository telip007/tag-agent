import Foundation
import OpenRouter

/// A streamed OpenAI Responses event, decoded to what the adapter needs.
enum ResponsesEvent: Sendable, Equatable {
    /// More text of the message at output `index`.
    case textDelta(index: Int, text: String)
    /// More reasoning of the reasoning item at output `index`.
    case reasoningDelta(index: Int, text: String)
    /// A reasoning summary part `part` began.
    case reasoningPartAdded(index: Int, part: Int)
    /// A function call began at output `index`.
    case toolCallStarted(index: Int, name: String)
    /// More arguments of the function call at output `index`.
    case argumentsDelta(index: Int, text: String)
    /// The output item at `index` is complete.
    case itemDone(index: Int, item: JSONValue)
    /// The response completed.
    case completed(Usage?)
    /// The response failed, was cut short, or the stream reported an error.
    case failed(ProviderError)
    /// An event the adapter doesn't need.
    case ignored

    /// Decodes an event's `data`.
    ///
    /// - Parameters:
    ///   - data: The server-sent event's data, a JSON object.
    ///   - provider: The provider, for errors.
    init(data: String, provider: ProviderID) {
        guard let json = try? JSONDecoder().decode(JSONValue.self, from: Data(data.utf8)),
            let type = json["type"]?.string
        else {
            self = data == "[DONE]" ? .ignored : .failed(.malformedResponse(provider, detail: "An event wasn't JSON."))
            return
        }
        let index = json["output_index"]?.int ?? 0
        switch type {
        case "response.output_text.delta", "response.refusal.delta":
            self = .textDelta(index: index, text: json["delta"]?.string ?? "")
        case "response.reasoning_summary_text.delta", "response.reasoning_text.delta":
            self = .reasoningDelta(index: index, text: json["delta"]?.string ?? "")
        case "response.reasoning_summary_part.added":
            self = .reasoningPartAdded(index: index, part: json["summary_index"]?.int ?? 0)
        case "response.output_item.added":
            let item = json["item"]
            self =
                item?["type"]?.string == "function_call"
                ? .toolCallStarted(index: index, name: item?["name"]?.string ?? "") : .ignored
        case "response.function_call_arguments.delta":
            self = .argumentsDelta(index: index, text: json["delta"]?.string ?? "")
        case "response.output_item.done":
            self = json["item"].map { .itemDone(index: index, item: $0) } ?? .ignored
        case "response.completed":
            self = .completed(Self.usage(in: json["response"]?["usage"]))
        case "response.failed", "response.incomplete", "error":
            self = .failed(Self.failure(type: type, json: json, provider: provider))
        default:
            self = .ignored
        }
    }

    private static func usage(in json: JSONValue?) -> Usage? {
        guard let input = json?["input_tokens"]?.int, let output = json?["output_tokens"]?.int else {
            return nil
        }
        return Usage(inputTokens: input, outputTokens: output)
    }

    private static func failure(type: String, json: JSONValue, provider: ProviderID) -> ProviderError {
        let response = json["response"]
        if type == "response.incomplete" {
            let reason = response?["incomplete_details"]?["reason"]?.string ?? "no reason given"
            return .unavailable(provider, detail: "The reply stopped early (\(reason)).")
        }
        let error = response?["error"] ?? json["error"] ?? json
        return ResponsesError.map(
            provider: provider, status: nil, code: error["code"]?.string,
            message: error["message"]?.string ?? "The response failed.", param: error["param"]?.string)
    }
}

/// Builds a reply from the events of one response.
struct ResponsesAccumulator {
    private struct Call {
        var name: String
        var arguments = ""
        var done: ToolCall?
    }

    let provider: ProviderID
    private var texts: [Int: String] = [:]
    private var reasoning: [Int: String] = [:]
    private var calls: [Int: Call] = [:]
    private var replay: [Int: ReplayItem] = [:]
    private var usage: Usage?
    private var completed = false

    init(provider: ProviderID) {
        self.provider = provider
    }

    /// Takes in an event.
    ///
    /// - Returns: What the event adds to the streaming reply, if anything.
    /// - Throws: The ``ProviderError`` of a failed response.
    mutating func apply(_ event: ResponsesEvent) throws -> ReplyDelta? {
        switch event {
        case .textDelta(let index, let text):
            texts[index, default: ""] += text
            return text.isEmpty ? nil : .text(text)
        case .reasoningDelta(let index, let text):
            reasoning[index, default: ""] += text
            return text.isEmpty ? nil : .reasoning(text)
        case .reasoningPartAdded(let index, let part):
            guard part > 0 else {
                return nil
            }
            reasoning[index, default: ""] += "\n\n"
            return .reasoning("\n\n")
        case .toolCallStarted(let index, let name):
            calls[index] = Call(name: name)
            return .toolCall(name: name)
        case .argumentsDelta(let index, let text):
            calls[index]?.arguments += text
            return nil
        case .itemDone(let index, let item):
            finish(item, at: index)
            return nil
        case .completed(let usage):
            self.usage = usage
            completed = true
            return nil
        case .failed(let error):
            throw error
        case .ignored:
            return nil
        }
    }

    /// The complete reply.
    ///
    /// - Throws: ``ProviderError/malformedResponse(_:detail:)`` when the
    ///   stream ended before `response.completed` or left a call unfinished.
    func reply() throws -> ModelReply {
        guard completed else {
            throw ProviderError.malformedResponse(provider, detail: "The stream ended before the reply was complete.")
        }
        var toolCalls: [ToolCall] = []
        for index in calls.keys.sorted() {
            guard let call = calls[index]?.done else {
                throw ProviderError.malformedResponse(provider, detail: "A tool call was left unfinished.")
            }
            toolCalls.append(call)
        }
        let text = Self.joined(texts, separator: "")
        let message = AssistantMessage(
            text: text, reasoning: Self.joined(reasoning, separator: "\n\n"),
            replay: replay.keys.sorted().compactMap { replay[$0] }, toolCalls: toolCalls)
        return ModelReply(message: message, usage: usage)
    }

    private mutating func finish(_ item: JSONValue, at index: Int) {
        switch item["type"]?.string {
        case "message":
            let parts = item["content"]?.array ?? []
            texts[index] = parts.compactMap { $0["text"]?.string ?? $0["refusal"]?.string }.joined()
        case "function_call":
            let callID = item["call_id"]?.string ?? item["id"]?.string ?? ""
            let name = item["name"]?.string ?? calls[index]?.name ?? ""
            let arguments = item["arguments"]?.string ?? calls[index]?.arguments ?? ""
            calls[index, default: Call(name: name)].done = ToolCall(id: callID, name: name, arguments: arguments)
        case "reasoning":
            let summary = (item["summary"]?.array ?? []).compactMap { $0["text"]?.string }.joined(separator: "\n\n")
            if !summary.isEmpty {
                reasoning[index] = summary
            }
            // Without its encrypted content a reasoning item can't be sent
            // back: nothing is stored server-side (`store: false`).
            if item["encrypted_content"]?.string != nil {
                replay[index] = ReplayItem(format: .responses, payload: item)
            }
        default:
            break
        }
    }

    private static func joined(_ parts: [Int: String], separator: String) -> String? {
        let text = parts.keys.sorted().compactMap { parts[$0] }.filter { !$0.isEmpty }.joined(separator: separator)
        return text.isEmpty ? nil : text
    }
}

/// Turns OpenAI Responses errors into ``ProviderError``s, including the
/// codes of ChatGPT plan usage.
enum ResponsesError {
    /// The error for a non-2xx response before the stream opened. The body
    /// is `{"error":{"code","message","param"}}`, `{"detail":"…"}`, or text.
    static func from(status: Int, body: String, provider: ProviderID) -> ProviderError {
        let json = try? JSONDecoder().decode(JSONValue.self, from: Data(body.utf8))
        let error = json?["error"]
        let message =
            error?["message"]?.string ?? error?.string ?? json?["detail"]?.string ?? json?["message"]?.string
            ?? body.trimmingCharacters(in: .whitespacesAndNewlines)
        return map(
            provider: provider, status: status, code: error?["code"]?.string, message: message,
            param: error?["param"]?.string)
    }

    /// The error for a code and message, with the HTTP status when there is one.
    static func map(provider: ProviderID, status: Int?, code: String?, message: String, param: String?) -> ProviderError
    {
        switch code {
        case "subscription_sharing_usage_limit_exceeded":
            return .usageLimit(provider, detail: message, manageURL: ChatGPTOAuth.usageURL)
        case "subscription_sharing_usage_unavailable", "subscription_sharing_user_unavailable":
            return .unavailable(provider, detail: message)
        case "subscription_sharing_user_not_eligible":
            return .notEligible(provider, detail: message)
        case "subscription_sharing_unsupported_capability":
            return .unsupported(provider, detail: param.map { "\(message) (\($0))" } ?? message)
        case "subscription_sharing_invalid_user":
            return .signInRequired(provider, detail: message)
        default:
            break
        }
        let detail = code.map { "\(message) (\($0))" } ?? message
        switch status {
        case 401: return .signInRequired(provider, detail: detail)
        case 503: return .unavailable(provider, detail: detail)
        case let status?: return .http(provider, status: status, detail: detail)
        case nil: return .malformedResponse(provider, detail: detail)
        }
    }
}
