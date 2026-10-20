import Foundation
import ModelKit
import SessionKit
import Testing

@testable import TagKit

@MainActor
struct NativeContextTests {
    @Test func smallResultsStayExactWhileLargeResultsGetActionableBoundedReferences() async throws {
        let fixture = ControllerFixture()
        let store = try await SQLiteSessionStore.open(directory: fixture.directory.appending(path: "sessions"))
        let summary = try await store.create(workspace: fixture.directory.path, context: savedContext)
        let context = NativeContext(store: store, sessionID: summary.id, workingDirectory: fixture.directory)
        let call = ToolCall(id: "run", name: "bash", arguments: "{}")
        let small = try await context.admit("small\n", call: call, failed: false, budget: 1024)
        #expect(small.content == "small\n")
        #expect(small.reference == nil)
        let raw = String(repeating: "test passed\n", count: 2000) + "FAILED final_test expected 7 got 9\n"
        let admitted = try await context.admit(raw, call: call, failed: true, budget: 1024)
        let reference = try #require(admitted.reference)
        #expect(admitted.content.utf8.count <= 1024)
        #expect(admitted.content.contains(reference.id))
        #expect(admitted.content.contains("read_output"))
        #expect(admitted.content.contains("FAILED final_test expected 7 got 9"))
        let hits = try await store.searchOutputs(summary.id, query: "final_test", outputID: reference.id)
        #expect(hits.first?.text.contains("FAILED final_test expected 7 got 9") == true)
    }

    @Test func escapedUnicodeAndMetadataFitTheCompleteEnvelope() async throws {
        let fixture = ControllerFixture()
        let store = try await SQLiteSessionStore.open(directory: fixture.directory.appending(path: "sessions"))
        let summary = try await store.create(workspace: fixture.directory.path, context: savedContext)
        let context = NativeContext(store: store, sessionID: summary.id, workingDirectory: fixture.directory)
        let call = ToolCall(id: "zeroes", name: "bash", arguments: "{}")
        let admitted = try await context.admit(
            String(repeating: "猫\u{0}\\\"\n", count: 1000), call: call, failed: false, budget: 1024)
        #expect(admitted.content.utf8.count <= 1024)
        #expect(try JSONSerialization.jsonObject(with: Data(admitted.content.utf8)) is [String: Any])
        let reference = try #require(admitted.reference)
        let tool = try #require(context.tools.first { $0.name == "read_output" })
        let page = try await tool.function("{\"output_id\":\"\(reference.id)\",\"offset\":0,\"max_bytes\":100}")
        #expect(page.utf8.count <= 16_384)
        let decoded = try #require(try JSONSerialization.jsonObject(with: Data(page.utf8)) as? [String: Any])
        #expect((decoded["text"] as? String)?.hasPrefix("猫\u{0}\\\"\n") == true)
    }

    @Test func agentArchivesBeforeJournalingAndResumedToolsCanReadTheSameEvidence() async throws {
        let fixture = ControllerFixture()
        let store = try await SQLiteSessionStore.open(directory: fixture.directory.appending(path: "sessions"))
        let summary = try await store.create(workspace: fixture.directory.path, context: savedContext)
        let context = NativeContext(store: store, sessionID: summary.id, workingDirectory: fixture.directory)
        let raw = String(repeating: "retained\n", count: 10_000) + "exact tail"
        let tool = ToolDefinition(name: "large", description: "fixture", parameters: [:]) { _ in raw }
        let call = ToolCall(id: "large-call", name: "large", arguments: "{}")
        let model = ScriptedModel([AssistantMessage(toolCalls: [call]), AssistantMessage(text: "done")])
        let terminal = Terminal(["inspect"])
        let agent = Agent(
            model: { model.active }, tools: [tool], environment: .fake,
            journal: AgentJournal(store: store, snapshot: try await store.load(summary.id)), context: context,
            output: terminal.record, input: { terminal.inputs.isEmpty ? nil : terminal.inputs.removeFirst() })
        try await agent.run()
        #expect(model.toolNames.first?.contains("read_output") == true)
        let delivered = try #require(model.conversations.last?.last)
        guard case .tool(_, _, let output) = delivered else {
            Issue.record("Missing tool result")
            return
        }
        #expect(output.utf8.count <= 16_384)
        #expect(!output.contains(raw))
        let reopened = try await SQLiteSessionStore.open(directory: store.directory)
        let hits = try await reopened.searchOutputs(summary.id, query: "exact tail")
        let hit = try #require(hits.first)
        #expect(hit.reference.callID == "large-call")
        #expect(hit.text.contains("exact tail"))
        #expect(
            try await reopened.entries(summary.id).contains { entry in
                if case .toolFinished(let result) = entry.event { return result.output == output }
                return false
            })
    }

    @Test func storageFailureAfterAnEffectStopsTheRemainingBatchWithoutRepeatingIt() async throws {
        let fixture = ControllerFixture()
        let store = try await SQLiteSessionStore.open(directory: fixture.directory.appending(path: "sessions"))
        let summary = try await store.create(workspace: fixture.directory.path, context: savedContext)
        let context = NativeContext(
            store: store, sessionID: summary.id, workingDirectory: fixture.directory,
            limits: OutputLimits(perOutput: 100_000, perSession: 1))
        let firstFile = fixture.directory.appending(path: "first-effect")
        let secondFile = fixture.directory.appending(path: "second-effect")
        let first = ToolDefinition(name: "first", description: "fixture", parameters: [:]) { _ in
            try Data("once".utf8).write(to: firstFile, options: .withoutOverwriting)
            return String(repeating: "large", count: 10_000)
        }
        let second = ToolDefinition(name: "second", description: "fixture", parameters: [:]) { _ in
            try Data("should not run".utf8).write(to: secondFile)
            return "done"
        }
        let model = ScriptedModel([
            AssistantMessage(toolCalls: [
                ToolCall(id: "one", name: "first", arguments: "{}"),
                ToolCall(id: "two", name: "second", arguments: "{}"),
            ])
        ])
        let terminal = Terminal(["run"])
        let agent = Agent(
            model: { model.active }, tools: [first, second], environment: .fake,
            journal: AgentJournal(store: store, snapshot: try await store.load(summary.id)), context: context,
            output: terminal.record, input: { terminal.inputs.isEmpty ? nil : terminal.inputs.removeFirst() })
        await #expect(throws: OutputError.quotaExceeded) { try await agent.run() }
        #expect(try String(contentsOf: firstFile, encoding: .utf8) == "once")
        #expect(!FileManager.default.fileExists(atPath: secondFile.path))
        #expect(model.conversations.count == 1)
        _ = try await store.recover(summary.id)
        #expect(!FileManager.default.fileExists(atPath: secondFile.path))
    }

    private var savedContext: SessionContext {
        SessionContext(prompt: "trusted", model: Models.codex.ref, effort: nil)
    }
}
