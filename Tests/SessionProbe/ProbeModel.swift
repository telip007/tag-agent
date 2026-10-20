import Foundation
import ModelKit

final class ProbeModel: ModelKit.ChatModel {
    let boundary: ProbeBoundary
    let providerIDFile: URL
    private var step = 0

    init(boundary: ProbeBoundary, providerIDFile: URL) {
        self.boundary = boundary
        self.providerIDFile = providerIDFile
    }

    func reply(
        to conversation: [Message], tools: [ToolSpec], options: ReplyOptions, onDelta: (ReplyDelta) -> Void
    ) async throws -> ModelReply {
        step += 1
        try options.sessionID.write(to: providerIDFile, atomically: true, encoding: .utf8)
        if step == 1 {
            onDelta(.text("uncommitted stream"))
            try await boundary.pauseIf("stream")
            let replay = try JSONDecoder().decode(
                ReplayItem.self, from: Data(#"{"format":"responses","payload":{"opaque":"retained fixture"}}"#.utf8))
            return ModelReply(
                message: AssistantMessage(
                    text: "Will write twice.", reasoning: "fixture reasoning", replay: [replay],
                    toolCalls: [
                        ToolCall(id: "first", name: "probe_write", arguments: "{}"),
                        ToolCall(id: "second", name: "probe_write", arguments: "{}"),
                    ]),
                usage: Usage(inputTokens: 10, outputTokens: 2, cost: 0.125))
        }
        try await boundary.pauseIf("follow-up")
        return ModelReply(
            message: AssistantMessage(text: "done"), usage: Usage(inputTokens: 20, outputTokens: 3, cost: 0.25))
    }
}
