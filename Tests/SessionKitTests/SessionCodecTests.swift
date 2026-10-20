import Foundation
import ModelKit
import Testing

@testable import SessionKit

struct SessionCodecTests {
    @Test func everyDurableBoundaryRoundTrips() throws {
        let call = ToolCall(id: "tool-1", name: "edit_file", arguments: "{}")
        let events: [SessionEvent] = [
            .context(
                SessionContext(prompt: "current", model: ModelRef(provider: .codex, model: "test"), effort: "high")),
            .inferenceStarted,
            .assistant(
                SessionAssistant(
                    message: AssistantMessage(reasoning: "thinking", toolCalls: [call]),
                    usage: Usage(inputTokens: 9, outputTokens: 2, cachedInputTokens: 0))),
            .toolStarted(call),
            .toolFinished(SessionToolResult(call: call, output: "done", failed: false, durationMilliseconds: 12)),
            .failure(SessionFailure(message: "interrupted", recovery: "inspect the workspace")),
        ]
        for event in events {
            #expect(try SessionCodec.decode(SessionCodec.encode(event)) == event)
        }
    }

    @Test func eventsHaveAnExplicitVersionAndKind() throws {
        let event = SessionEvent.assistant(
            SessionAssistant(message: AssistantMessage(text: "saved"), usage: nil))
        let data = try SessionCodec.encode(event)
        #expect(try SessionCodec.decode(data) == event)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["version"] as? Int == 1)
        let payload = try #require(json["event"] as? [String: Any])
        #expect(payload["kind"] as? String == "assistant")
    }

    @Test func aFuturePayloadNeverBecomesEmptyHistory() {
        let future = Data("{\"version\":2,\"event\":{\"kind\":\"inferenceStarted\"}}".utf8)
        #expect(throws: SessionError.unsupportedVersion(2)) { try SessionCodec.decode(future) }
        #expect(throws: (any Error).self) { try SessionCodec.decode(Data("broken".utf8)) }
    }

    @Test func rawInputAndModelInputRemainDistinct() throws {
        let user = SessionEvent.user(
            SessionUser(
                raw: "hello", message: "<environment_update>date: 2026-10-20</environment_update>\n\nhello",
                date: "2026-10-20", references: []))
        #expect(try SessionCodec.decode(SessionCodec.encode(user)) == user)
    }
}
