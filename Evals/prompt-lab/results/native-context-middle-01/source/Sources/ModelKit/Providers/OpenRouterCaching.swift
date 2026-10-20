import Foundation
import OpenRouter

extension OpenRouterChatModel {
    /// Opt-in providers and routers with an unknown target need content
    /// markers. Fixed automatic-cache families keep their native behavior.
    static func cachedMessages(_ conversation: [Message], model: String) -> [ChatMessage] {
        let model = model.trimmingCharacters(in: CharacterSet(charactersIn: "~"))
        guard
            model.hasPrefix("anthropic/") || model.hasPrefix("qwen/") || model.hasPrefix("openrouter/")
                || model == "deepseek/deepseek-v3.2"
        else {
            return conversation.map(chatMessage)
        }
        let boundaries = boundaries(in: conversation)
        let system = conversation.lastIndex { if case .system = $0 { true } else { false } }
        return conversation.enumerated().map { index, message in
            let cached = boundaries.contains(index) || index == system
            switch message {
            case .system(let text):
                return .system(.init(content: .init(value2: [part(text, cached: cached)]), role: .system))
            case .user(let text):
                return .user([.text(part(text, cached: cached))])
            case .tool(let callID, _, let text):
                return .tool(
                    .init(content: .init(value2: [.text(part(text, cached: cached))]), role: .tool, toolCallId: callID))
            case .assistant:
                return chatMessage(message)
            }
        }
    }

    /// The last two user/result turns, counting a batch of results as one.
    private static func boundaries(in conversation: [Message]) -> [Int] {
        var indices: [Int] = []
        for (index, message) in conversation.enumerated() {
            switch message {
            case .user:
                indices.append(index)
            case .tool:
                if index + 1 < conversation.count, case .tool = conversation[index + 1] { continue }
                indices.append(index)
            default:
                break
            }
        }
        return Array(indices.suffix(2))
    }

    // Decode the SDK's extensible directive without importing its runtime container.
    private static let cache = try? JSONDecoder().decode(
        Components.Schemas.ChatContentCacheControl.self, from: Data(#"{"type":"ephemeral"}"#.utf8))

    private static func part(_ text: String, cached: Bool) -> Components.Schemas.ChatContentText {
        .init(
            cacheControl: cached ? cache : nil,
            text: text, _type: .text)
    }
}
