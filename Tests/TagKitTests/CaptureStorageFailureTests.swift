import Foundation
import ModelKit
import SessionKit
import Testing

@testable import TagKit

@MainActor
struct CaptureStorageFailureTests {
    @Test(arguments: ["bash", "analyze_output", "batch_execute"], ["write", "read"])
    func postEffectSpoolFailureStopsDispatch(toolName: String, operation: String) async throws {
        let fixture = ControllerFixture()
        let store = try await SQLiteSessionStore.open(directory: fixture.directory.appending(path: "sessions"))
        let summary = try await store.create(
            workspace: fixture.directory.path,
            context: SessionContext(prompt: "fixture", model: Models.codex.ref, effort: nil))
        let source = try await store.saveOutput(summary.id, text: "input", source: "fixture")
        let factory: @Sendable () throws -> CaptureSpool = {
            if operation == "write" {
                return try CaptureSpool(write: { _, _ in throw POSIXError(.ENOSPC) })
            }
            return try CaptureSpool(read: { _ in throw POSIXError(.EIO) })
        }
        let directory = fixture.directory
        let command = "touch first_effect; printf captured"
        let shell = ToolDefinition.bash(workingDirectory: directory)
            .capturing { _ in
                try await ProcessCapture.run("bash", ["-c", command], in: directory, makeSpool: factory)
            }.withContextExecutor(
                ContextCommandExecutor(directory: directory, protected: .tagConfig, makeSpool: factory))
        let later = ToolDefinition(name: "later", description: "fixture", parameters: [:]) { _ in
            try Data().write(to: directory.appending(path: "later_effect"))
            return "done"
        }
        let arguments = try arguments(for: toolName, sourceID: source.id, command: command)
        let calls = [
            ToolCall(id: "first", name: toolName, arguments: arguments),
            ToolCall(id: "later", name: "later", arguments: "{}"),
        ]
        let model = ScriptedModel([AssistantMessage(toolCalls: calls), AssistantMessage(text: "must not infer")])
        let terminal = Terminal(["run"])
        let agent = Agent(
            model: { model.active }, tools: [shell, later], environment: .fake,
            journal: AgentJournal(store: store, snapshot: try await store.load(summary.id)),
            context: NativeContext(store: store, sessionID: summary.id, workingDirectory: directory),
            output: terminal.record, input: { terminal.inputs.isEmpty ? nil : terminal.inputs.removeFirst() })
        await #expect(throws: ContextStorageFailure.self) { try await agent.run() }
        try await verifyStopped(directory: directory, model: model, store: store, id: summary.id)
    }

    private func verifyStopped(
        directory: URL, model: ScriptedModel, store: SQLiteSessionStore, id: UUID
    ) async throws {
        #expect(FileManager.default.fileExists(atPath: directory.appending(path: "first_effect").path))
        #expect(!FileManager.default.fileExists(atPath: directory.appending(path: "later_effect").path))
        #expect(!FileManager.default.fileExists(atPath: directory.appending(path: "later_batch_effect").path))
        #expect(model.conversations.count == 1)
        let entries = try await store.entries(id)
        #expect(
            !entries.contains {
                if case .toolFinished = $0.event { return true }
                return false
            })
        let recovered = try await store.recover(id)
        #expect(
            recovered.entries.contains {
                if case .toolFinished(let result) = $0.event {
                    return result.call.id == "first" && result.failed
                        && result.output.contains("side effects are unknown")
                }
                return false
            })
    }

    private func arguments(for tool: String, sourceID: String, command: String) throws -> String {
        switch tool {
        case "analyze_output":
            return try ContextText.json(["output_id": sourceID, "command": command])
        case "batch_execute":
            return try ContextText.json([
                "commands": [["command": command], ["command": "touch later_batch_effect"]]
            ])
        default: return try ContextText.json(["command": command])
        }
    }
}
