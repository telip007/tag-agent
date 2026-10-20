import Foundation
import ModelKit
import SessionKit
import Testing

@testable import TagKit

@MainActor
struct ContextAnalysisTests {
    @Test func analysisUsesEveryRetainedByteInsteadOfSparseSearchMatches() async throws {
        let fixture = ControllerFixture()
        let store = try await SQLiteSessionStore.open(directory: fixture.directory.appending(path: "sessions"))
        let session = try await store.create(workspace: fixture.directory.path, context: savedContext)
        let values = (1...10_000).map(String.init).joined(separator: "\n") + "\n"
        let original = try await store.saveOutput(session.id, text: values, source: "all values")
        let context = NativeContext(store: store, sessionID: session.id, workingDirectory: fixture.directory)
            .withExecution([.bash(workingDirectory: fixture.directory)])
        let tool = try #require(context.tools.first { $0.name == "analyze_output" })
        let args = try ContextText.json([
            "output_id": original.id, "command": "awk '{s += $1} END {print s}'",
        ])
        let reply = try await tool.function(args)
        let result = try #require(try JSONSerialization.jsonObject(with: Data(reply.utf8)) as? [String: Any])
        #expect(result["input_output_id"] as? String == original.id)
        #expect(result["source_complete"] as? Bool == true)
        let outputID = try #require(result["output_id"] as? String)
        #expect(try await store.loadOutput(session.id, id: outputID).text == "50005000\n")
        #expect(reply.utf8.count <= 16_384)
    }

    @Test func analysisKeepsInputBytesAndFailureStatusWithoutExposingStorePaths() async throws {
        let fixture = ControllerFixture()
        let store = try await SQLiteSessionStore.open(directory: fixture.directory.appending(path: "sessions"))
        let session = try await store.create(workspace: fixture.directory.path, context: savedContext)
        let original = try await store.saveOutput(
            session.id, text: "\u{FEFF}a\u{0}", source: "partial", complete: false)
        let context = NativeContext(store: store, sessionID: session.id, workingDirectory: fixture.directory)
            .withExecution([.bash(workingDirectory: fixture.directory)])
        let call = ToolCall(
            id: "analysis", name: "analyze_output",
            arguments: try ContextText.json([
                "output_id": original.id,
                // CI enables Swift backtraces; the system Python launcher emits its runtime warning on stderr.
                // Isolate this exact-byte probe from that harness debug setting.
                "command":
                    "env -u SWIFT_BACKTRACE python3 -c 'import sys; print(sys.stdin.buffer.read().hex()); sys.exit(7)'",
            ]))
        let outcome = try await context.invoke(call, budget: 512)
        #expect(outcome.failed)
        #expect(outcome.content.utf8.count <= 512)
        #expect(!outcome.content.contains(store.directory.path))
        let reply = try #require(try JSONSerialization.jsonObject(with: Data(outcome.content.utf8)) as? [String: Any])
        #expect(reply["source_complete"] as? Bool == false)
        #expect(reply["exit_code"] as? Int == 7)
        let id = try #require(reply["output_id"] as? String)
        let captured = try await store.loadOutput(session.id, id: id)
        #expect(captured.text == "efbbbf6100\n")
    }

    @Test func foreignInputCannotRunAnAnalysisCommand() async throws {
        let fixture = ControllerFixture()
        let store = try await SQLiteSessionStore.open(directory: fixture.directory.appending(path: "sessions"))
        let first = try await store.create(workspace: fixture.directory.path, context: savedContext)
        let second = try await store.create(workspace: "/other", context: savedContext)
        let original = try await store.saveOutput(second.id, text: "foreign", source: "private")
        let context = NativeContext(store: store, sessionID: first.id, workingDirectory: fixture.directory)
            .withExecution([.bash(workingDirectory: fixture.directory)])
        let tool = try #require(context.tools.first { $0.name == "analyze_output" })
        await #expect(throws: OutputError.notFound) {
            try await tool.function(try ContextText.json(["output_id": original.id, "command": "touch forbidden"]))
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.directory.appending(path: "forbidden").path))
    }

    private var savedContext: SessionContext { SessionContext(prompt: "test", model: Models.codex.ref, effort: nil) }
}

extension ContextAnalysisTests {
    @Test func realAgentComputeResultsStayBoundedInBothJournalAndUI() async throws {
        let fixture = ControllerFixture()
        let store = try await SQLiteSessionStore.open(directory: fixture.directory.appending(path: "sessions"))
        let session = try await store.create(workspace: fixture.directory.path, context: savedContext)
        let input = try await store.saveOutput(session.id, text: "1\n2\n3\n", source: "values")
        let context = NativeContext(store: store, sessionID: session.id, workingDirectory: fixture.directory)
        let calls = [
            ToolCall(
                id: "calc", name: "analyze_output",
                arguments: try ContextText.json([
                    "output_id": input.id, "command": "awk '{s += $1} END {print s}'",
                ])),
            ToolCall(
                id: "batch", name: "batch_execute",
                arguments: #"{"commands":[{"command":"head -c 80000 /dev/zero | tr '\\0' x; exit 7"}]}"#),
        ]
        let model = ScriptedModel([AssistantMessage(toolCalls: calls), AssistantMessage(text: "done")])
        let terminal = Terminal(["compute"])
        let agent = Agent(
            model: { model.active }, tools: [.bash(workingDirectory: fixture.directory)], environment: .fake,
            journal: AgentJournal(store: store, snapshot: try await store.load(session.id)), context: context,
            output: terminal.record, input: { terminal.inputs.isEmpty ? nil : terminal.inputs.removeFirst() })
        try await agent.run()
        let delivered = terminal.events.compactMap { event -> String? in
            if case .toolFinished(_, _, let output, _) = event { return output }
            return nil
        }
        #expect(delivered.count == 2)
        #expect(delivered.reduce(0) { $0 + $1.utf8.count } <= 32_768)
        #expect(
            terminal.events.contains {
                if case .toolFinished("batch_execute", _, _, true) = $0 { return true }
                return false
            })
        #expect(try await store.outputStatistics(session.id).outputCount == 4)
        let journal = try await store.entries(session.id).compactMap { entry -> String? in
            if case .toolFinished(let result) = entry.event { return result.output }
            return nil
        }
        #expect(journal == delivered)
    }
}
