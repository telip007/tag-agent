import Foundation
import ModelKit
import SessionKit
import Testing

@testable import TagKit

@MainActor
struct ContextHistoryTests {
    @Test func compactedDecisionsRemainSearchableAndExactlyReadable() async throws {
        let fixture = PersistentAgentFixture()
        let (store, session) = try await fixture.prepare()
        try await store.append(
            session.id,
            event: .assistant(
                SessionAssistant(
                    message: AssistantMessage(text: "earlier_marker decision" + String(repeating: ".", count: 1200)),
                    usage: nil)))
        try await store.append(
            session.id, event: .assistant(SessionAssistant(message: AssistantMessage(text: "recent"), usage: nil)))
        _ = try await store.compactContext(session.id, keepRecentGroups: 1)
        let context = NativeContext(store: store, sessionID: session.id, workingDirectory: fixture.directory)
        let search = try #require(context.tools.first { $0.name == "search_history" })
        let found = try await search.function(#"{"query":"earlier_marker"}"#)
        let matches = try #require(try decode(found)["matches"] as? [[String: Any]])
        #expect(matches.first?["sequence"] as? Int == 1)
        let read = try #require(context.tools.first { $0.name == "read_history" })
        let response = try decode(try await read.function(#"{"sequence":1}"#))
        let text = try #require(response["text"] as? String)
        let envelope = try decode(text)
        let event = try #require(envelope["event"] as? [String: Any])
        let value = try #require(event["value"] as? [String: Any])
        let message = try #require(value["message"] as? [String: Any])
        #expect(message["text"] as? String == "earlier_marker decision" + String(repeating: ".", count: 1200))
    }

    @Test func forgedSessionArgumentsCannotWidenHistoryTools() async throws {
        let fixture = PersistentAgentFixture()
        let (store, first) = try await fixture.prepare()
        let second = try await store.create(workspace: "/other", context: first.context)
        try await store.append(
            second.id,
            event: .assistant(SessionAssistant(message: AssistantMessage(text: "foreign_marker"), usage: nil)))
        let context = NativeContext(store: store, sessionID: first.id, workingDirectory: fixture.directory)
        let read = try #require(context.tools.first { $0.name == "read_history" })
        await #expect(throws: SessionError.notFound) {
            try await read.function("{\"sequence\":1,\"session_id\":\"\(second.id.uuidString)\"}")
        }
    }

    private func decode(_ text: String) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }
}

extension ContextHistoryTests {
    @Test func historyRetrievalSharesGroupBudgetsWithoutArchivingItsReplies() async throws {
        let fixture = PersistentAgentFixture()
        let (store, session) = try await fixture.prepare()
        try await store.append(
            session.id,
            event: .assistant(
                SessionAssistant(
                    message: AssistantMessage(text: String(repeating: "猫\u{0}\n", count: 4000)), usage: nil)))
        let context = NativeContext(store: store, sessionID: session.id, workingDirectory: fixture.directory)
        let calls = (1...64).map { ToolCall(id: "history-\($0)", name: "read_history", arguments: #"{"sequence":1}"#) }
        let model = ScriptedModel([AssistantMessage(toolCalls: calls), AssistantMessage(text: "done")])
        let terminal = Terminal(["read"])
        let agent = Agent(
            model: { model.active }, environment: .fake, context: context, output: terminal.record,
            input: { terminal.inputs.isEmpty ? nil : terminal.inputs.removeFirst() })
        try await agent.run()
        let results = try #require(model.conversations.last).compactMap { message -> String? in
            if case .tool(_, _, let text) = message { return text }
            return nil
        }
        #expect(results.count == 64)
        #expect(results.reduce(0) { $0 + $1.utf8.count } <= 32_768)
        #expect(try await store.outputStatistics(session.id).outputCount == 0)
    }
}
