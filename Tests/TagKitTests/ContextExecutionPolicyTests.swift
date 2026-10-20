import Foundation
import ModelKit
import SessionKit
import Testing

@testable import TagKit

@MainActor
struct ContextExecutionPolicyTests {
    @Test(arguments: [false, true])
    func contextCannotInventAnExecutorForAMissingOrCustomShell(custom: Bool) async throws {
        let fixture = ControllerFixture()
        let context = try await makeContext(fixture)
        let model = ScriptedModel([
            AssistantMessage(toolCalls: [
                ToolCall(
                    id: "batch", name: "batch_execute", arguments: #"{"commands":[{"command":"touch forbidden"}]}"#)
            ]),
            AssistantMessage(text: "done"),
        ])
        let terminal = Terminal(["inspect"])
        let customShell = ToolDefinition(name: "bash", description: "restricted host wrapper", parameters: [:]) { _ in
            "blocked"
        }
        let agent = Agent(
            model: { model.active }, tools: custom ? [customShell] : [], environment: .fake, context: context,
            output: terminal.record, input: { terminal.inputs.isEmpty ? nil : terminal.inputs.removeFirst() })
        try await agent.run()
        #expect(model.toolNames.first?.contains("batch_execute") == false)
        #expect(model.toolNames.first?.contains("analyze_output") == false)
        #expect(!FileManager.default.fileExists(atPath: fixture.directory.appending(path: "forbidden").path))
    }

    @Test func batchValidatesTheActualShellPolicyBeforeAnyCommandRuns() async throws {
        let fixture = ControllerFixture()
        let context = try await makeContext(fixture)
        let protected = fixture.directory.appending(path: "secret")
        try FileManager.default.createDirectory(at: protected, withIntermediateDirectories: true)
        try "private".write(to: protected.appending(path: "key"), atomically: true, encoding: .utf8)
        let command = "cat " + protected.appending(path: "key").path
        let args = try ContextText.json(["commands": [["command": "touch forbidden"], ["command": command]]])
        let model = ScriptedModel([
            AssistantMessage(toolCalls: [ToolCall(id: "batch", name: "batch_execute", arguments: args)]),
            AssistantMessage(text: "done"),
        ])
        let terminal = Terminal(["inspect"])
        let agent = Agent(
            model: { model.active },
            tools: [.bash(workingDirectory: fixture.directory, protecting: ProtectedPaths(directories: [protected]))],
            environment: .fake, context: context, output: terminal.record,
            input: { terminal.inputs.isEmpty ? nil : terminal.inputs.removeFirst() })
        try await agent.run()
        #expect(!FileManager.default.fileExists(atPath: fixture.directory.appending(path: "forbidden").path))
        #expect(try await context.store.outputStatistics(context.sessionID).outputCount == 0)
    }

    private func makeContext(_ fixture: ControllerFixture) async throws -> NativeContext {
        let store = try await SQLiteSessionStore.open(directory: fixture.directory.appending(path: "sessions"))
        let session = try await store.create(
            workspace: fixture.directory.path,
            context: SessionContext(prompt: "test", model: Models.codex.ref, effort: nil))
        return NativeContext(
            store: store, sessionID: session.id, workingDirectory: fixture.directory, protecting: .nothing)
    }
}
