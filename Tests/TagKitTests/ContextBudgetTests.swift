import Foundation
import ModelKit
import SessionKit
import Testing

@testable import TagKit

@MainActor
struct ContextBudgetTests {
    @Test func aToolBatchSharesOneAdmissionBudget() async throws {
        let fixture = ControllerFixture()
        let store = try await SQLiteSessionStore.open(directory: fixture.directory.appending(path: "sessions"))
        let saved = SessionContext(prompt: "trusted", model: Models.codex.ref, effort: nil)
        let summary = try await store.create(workspace: fixture.directory.path, context: saved)
        let context = NativeContext(store: store, sessionID: summary.id, workingDirectory: fixture.directory)
        let tool = ToolDefinition(name: "large", description: "fixture", parameters: [:]) { _ in
            String(repeating: "evidence\n", count: 1500)
        }
        let calls = (1...5).map { ToolCall(id: "call-\($0)", name: "large", arguments: "{}") }
        let model = ScriptedModel([AssistantMessage(toolCalls: calls), AssistantMessage(text: "done")])
        let terminal = Terminal(["inspect"])
        let agent = Agent(
            model: { model.active }, tools: [tool], environment: .fake,
            journal: AgentJournal(store: store, snapshot: try await store.load(summary.id)), context: context,
            output: terminal.record, input: { terminal.inputs.isEmpty ? nil : terminal.inputs.removeFirst() })
        try await agent.run()
        let results = try #require(model.conversations.last).compactMap { message -> String? in
            if case .tool(_, _, let content) = message { return content }
            return nil
        }
        #expect(results.count == 5)
        #expect(results.reduce(0) { $0 + $1.utf8.count } <= 32_768)
        #expect(try await store.outputStatistics(summary.id).outputCount == 5)
    }

    @Test func anOversizedToolBatchIsRejectedBeforeEffects() async throws {
        let fixture = ControllerFixture()
        let store = try await SQLiteSessionStore.open(directory: fixture.directory.appending(path: "sessions"))
        let saved = SessionContext(prompt: "trusted", model: Models.codex.ref, effort: nil)
        let summary = try await store.create(workspace: fixture.directory.path, context: saved)
        let context = NativeContext(store: store, sessionID: summary.id, workingDirectory: fixture.directory)
        let marker = fixture.directory.appending(path: "should-not-exist")
        let tool = ToolDefinition(name: "effect", description: "fixture", parameters: [:]) { _ in
            try Data("ran".utf8).write(to: marker)
            return "done"
        }
        let calls = (1...65).map { ToolCall(id: "call-\($0)", name: "effect", arguments: "{}") }
        let model = ScriptedModel([AssistantMessage(toolCalls: calls)])
        let terminal = Terminal(["inspect"])
        let agent = Agent(
            model: { model.active }, tools: [tool], environment: .fake,
            journal: AgentJournal(store: store, snapshot: try await store.load(summary.id)), context: context,
            output: terminal.record, input: { terminal.inputs.isEmpty ? nil : terminal.inputs.removeFirst() })
        try await agent.run()
        #expect(!FileManager.default.fileExists(atPath: marker.path))
        #expect(
            terminal.events.contains {
                if case .failure = $0 { return true }
                return false
            })
        let snapshot = try await store.recover(summary.id)
        #expect(
            !snapshot.entries.contains {
                if case .toolStarted = $0.event { return true }
                return false
            })
    }

    @Test func retrievalCannotWidenItsSessionAndDoesNotArchiveItsOwnResponse() async throws {
        let fixture = ControllerFixture()
        let store = try await SQLiteSessionStore.open(directory: fixture.directory.appending(path: "sessions"))
        let saved = SessionContext(prompt: "trusted", model: Models.codex.ref, effort: nil)
        let first = try await store.create(workspace: fixture.directory.path, context: saved)
        let second = try await store.create(workspace: fixture.directory.path, context: saved)
        let reference = try await store.saveOutput(second.id, text: "private evidence", source: "foreign")
        let context = NativeContext(store: store, sessionID: first.id, workingDirectory: fixture.directory)
        let read = try #require(context.tools.first { $0.name == "read_output" })
        let input = "{\"output_id\":\"\(reference.id)\",\"session_id\":\"\(second.id)\"}"
        await #expect(throws: OutputError.notFound) { try await read.function(input) }
        let own = try await store.saveOutput(first.id, text: "own evidence", source: "own")
        let model = ScriptedModel([
            AssistantMessage(toolCalls: [
                ToolCall(id: "read", name: "read_output", arguments: "{\"output_id\":\"\(own.id)\"}")
            ]),
            AssistantMessage(text: "done"),
        ])
        let terminal = Terminal(["read"])
        let agent = Agent(
            model: { model.active }, environment: .fake,
            journal: AgentJournal(store: store, snapshot: try await store.load(first.id)), context: context,
            output: terminal.record, input: { terminal.inputs.isEmpty ? nil : terminal.inputs.removeFirst() })
        try await agent.run()
        #expect(try await store.outputStatistics(first.id).outputCount == 1)
        #expect(try await store.outputStatistics(second.id).outputCount == 1)
    }
}
