import Foundation
import ModelKit
import SessionKit
import Testing

@testable import TagKit

@MainActor
struct ContextIndexTests {
    @Test func fileIndexRetainsAnImmutableOriginalWithActionableProvenance() async throws {
        let fixture = ControllerFixture()
        let store = try await SQLiteSessionStore.open(directory: fixture.directory.appending(path: "sessions"))
        let session = try await store.create(workspace: fixture.directory.path, context: savedContext)
        let file = fixture.directory.appending(path: "evidence.txt")
        try "猫\u{0}\noriginal_tail".write(to: file, atomically: true, encoding: .utf8)
        let context = NativeContext(store: store, sessionID: session.id, workingDirectory: fixture.directory)
        let index = try #require(context.tools.first { $0.name == "index_file" })
        let reply = try await index.function(#"{"path":"evidence.txt"}"#)
        let data = try #require(try JSONSerialization.jsonObject(with: Data(reply.utf8)) as? [String: Any])
        let id = try #require(data["output_id"] as? String)
        #expect(data["untrusted"] as? Bool == true)
        #expect(data["complete"] as? Bool == true)
        try "changed".write(to: file, atomically: true, encoding: .utf8)
        let reopened = try await SQLiteSessionStore.open(directory: store.directory)
        let page = try await reopened.readOutput(session.id, id: id, offset: 0, limit: 100)
        #expect(page.text == "猫\u{0}\noriginal_tail")
        #expect(page.reference.source == "file:evidence.txt")
        #expect(page.reference.sha256 == data["sha256"] as? String)
        #expect(try await reopened.searchOutputs(session.id, query: "original_tail").first?.reference.id == id)
    }

    @Test func indexingChecksSymlinksAndReportsPartialFileEvidence() async throws {
        let fixture = ControllerFixture()
        let store = try await SQLiteSessionStore.open(directory: fixture.directory.appending(path: "sessions"))
        let session = try await store.create(workspace: fixture.directory.path, context: savedContext)
        let secret = fixture.directory.appending(path: "secret")
        try FileManager.default.createDirectory(at: secret, withIntermediateDirectories: true)
        try "private".write(to: secret.appending(path: "key"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: fixture.directory.appending(path: "alias"), withDestinationURL: secret.appending(path: "key"))
        let context = NativeContext(
            store: store, sessionID: session.id, workingDirectory: fixture.directory,
            limits: OutputLimits(perOutput: 6), protecting: ProtectedPaths(directories: [secret]))
        let index = try #require(context.tools.first { $0.name == "index_file" })
        await #expect(throws: ToolError.self) { try await index.function(#"{"path":"alias"}"#) }
        try "猫\n猫\n".write(to: fixture.directory.appending(path: "large"), atomically: true, encoding: .utf8)
        let reply = try await index.function(#"{"path":"large"}"#)
        let data = try #require(try JSONSerialization.jsonObject(with: Data(reply.utf8)) as? [String: Any])
        #expect(data["complete"] as? Bool == false)
        let id = try #require(data["output_id"] as? String)
        #expect(try await store.readOutput(session.id, id: id, offset: 0, limit: 100).text == "猫\n")
    }

    @Test func agentIndicesUseGroupBudgetsWithoutRecursivelyArchivingTheirReplies() async throws {
        let fixture = ControllerFixture()
        let store = try await SQLiteSessionStore.open(directory: fixture.directory.appending(path: "sessions"))
        let summary = try await store.create(workspace: fixture.directory.path, context: savedContext)
        let path = String(repeating: "long_directory/", count: 30) + "file"
        let file = fixture.directory.appending(path: path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "retained".write(to: file, atomically: true, encoding: .utf8)
        let arguments = try #require(String(data: JSONEncoder().encode(["path": path]), encoding: .utf8))
        let context = NativeContext(store: store, sessionID: summary.id, workingDirectory: fixture.directory)
        let calls = (1...64).map { ToolCall(id: "index-\($0)", name: "index_file", arguments: arguments) }
        let model = ScriptedModel([AssistantMessage(toolCalls: calls), AssistantMessage(text: "done")])
        let terminal = Terminal(["index"])
        let agent = Agent(
            model: { model.active }, environment: .fake, context: context,
            output: terminal.record, input: { terminal.inputs.isEmpty ? nil : terminal.inputs.removeFirst() })
        try await agent.run()
        let replies = try #require(model.conversations.last).compactMap { message -> String? in
            if case .tool(_, _, let content) = message { return content }
            return nil
        }
        #expect(replies.count == 64)
        #expect(replies.reduce(0) { $0 + $1.utf8.count } <= 32_768)
        #expect(try await store.outputStatistics(summary.id).outputCount == 64)
        let hit = try #require(try await store.searchOutputs(summary.id, query: "retained").first)
        #expect(hit.reference.callID?.hasPrefix("index-") == true)
    }

    private var savedContext: SessionContext {
        SessionContext(prompt: "trusted", model: Models.codex.ref, effort: nil)
    }
}

extension ContextIndexTests {
    @Test func nativeStorageFailureStopsTheRestOfAToolGroup() async throws {
        let fixture = ControllerFixture()
        let store = try await SQLiteSessionStore.open(directory: fixture.directory.appending(path: "sessions"))
        let session = try await store.create(workspace: fixture.directory.path, context: savedContext)
        try "x".write(to: fixture.directory.appending(path: "file"), atomically: true, encoding: .utf8)
        let context = NativeContext(
            store: store, sessionID: session.id, workingDirectory: fixture.directory,
            limits: OutputLimits(perSession: 1))
        let model = ScriptedModel([
            AssistantMessage(toolCalls: [
                ToolCall(id: "one", name: "index_file", arguments: #"{"path":"file"}"#),
                ToolCall(id: "two", name: "index_file", arguments: #"{"path":"file"}"#),
                ToolCall(id: "three", name: "bash", arguments: #"{"command":"touch should-not-run"}"#),
            ])
        ])
        let terminal = Terminal(["index"])
        let agent = Agent(
            model: { model.active }, tools: [.bash(workingDirectory: fixture.directory)], environment: .fake,
            journal: AgentJournal(store: store, snapshot: try await store.load(session.id)), context: context,
            output: terminal.record, input: { terminal.inputs.isEmpty ? nil : terminal.inputs.removeFirst() })
        await #expect(throws: ContextStorageFailure.self) { try await agent.run() }
        #expect(try await store.outputStatistics(session.id).outputCount == 1)
        #expect(!FileManager.default.fileExists(atPath: fixture.directory.appending(path: "should-not-run").path))
        #expect(model.conversations.count == 1)
    }
}
