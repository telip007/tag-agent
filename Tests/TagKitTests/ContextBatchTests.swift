import Foundation
import ModelKit
import SessionKit
import Testing

@testable import TagKit

@MainActor
struct ContextBatchTests {
    @Test func batchRunsInOrderPreservesFailuresAndQueriesOnlyItsOwnOutputs() async throws {
        let fixture = ControllerFixture()
        let context = try await makeContext(fixture)
        let foreign = try await context.store.saveOutput(
            context.sessionID, text: "FOREIGN needle", source: "older output")
        let call = ToolCall(
            id: "batch", name: "batch_execute",
            arguments:
                #"{"commands":[{"label":"first","command":"printf first > order; printf 'BATCH needle first'"},{"label":"failure","command":"printf second >> order; printf 'BATCH needle failure'; exit 7"},{"command":"cat order"}],"queries":["needle"]}"#
        )
        let outcome = try await context.invoke(call, budget: 1024)
        #expect(outcome.failed)
        #expect(outcome.content.utf8.count <= 1024)
        #expect(try String(contentsOf: fixture.directory.appending(path: "order"), encoding: .utf8) == "firstsecond")
        let reply = try decode(outcome.content)
        let manifestID = try #require(reply["output_id"] as? String)
        let manifest = try decode(try await context.store.loadOutput(context.sessionID, id: manifestID).text)
        let commands = try #require(manifest["commands"] as? [[String: Any]])
        #expect(commands.count == 3)
        #expect(commands[1]["exit_code"] as? Int == 7)
        #expect(commands[1]["failed"] as? Bool == true)
        let ids = commands.compactMap { $0["output_id"] as? String }
        let matches = try #require(reply["matches"] as? [[String: Any]])
        #expect(!matches.isEmpty)
        #expect(matches.allSatisfy { ids.contains($0["output_id"] as? String ?? "") })
        #expect(matches.allSatisfy { $0["output_id"] as? String != foreign.id })
        let last = try #require(ids.last)
        #expect(try await context.store.loadOutput(context.sessionID, id: last).text == "firstsecond")
        #expect(try await context.store.outputStatistics(context.sessionID).outputCount == 5)
    }

    @Test func everyInputIsValidatedBeforeTheFirstCommandRuns() async throws {
        let fixture = ControllerFixture()
        let context = try await makeContext(fixture)
        let tool = try #require(context.tools.first { $0.name == "batch_execute" })
        await #expect(throws: ToolError.self) {
            try await tool.function(#"{"commands":[{"command":"touch forbidden"}],"queries":[""]}"#)
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.directory.appending(path: "forbidden").path))
    }

    @Test func storageFailureAfterAnEffectStopsLaterBatchCommands() async throws {
        let fixture = ControllerFixture()
        let context = try await makeContext(fixture, limits: OutputLimits(perSession: 1))
        let tool = try #require(context.tools.first { $0.name == "batch_execute" })
        await #expect(throws: ContextStorageFailure.self) {
            try await tool.function(
                #"{"commands":[{"command":"touch first; printf oversized"},{"command":"touch forbidden"}]}"#)
        }
        #expect(FileManager.default.fileExists(atPath: fixture.directory.appending(path: "first").path))
        #expect(!FileManager.default.fileExists(atPath: fixture.directory.appending(path: "forbidden").path))
    }

    @Test func incompleteCaptureStopsTheRemainingCommandsAndRecordsWhy() async throws {
        let fixture = ControllerFixture()
        let context = try await makeContext(fixture, limits: OutputLimits(perOutput: 4096))
        let tool = try #require(context.tools.first { $0.name == "batch_execute" })
        let result = try await tool.function(
            #"{"commands":[{"command":"head -c 10000 /dev/zero | tr '\\0' x"},{"command":"touch forbidden"}]}"#)
        let reply = try decode(result)
        let id = try #require(reply["output_id"] as? String)
        let manifest = try decode(try await context.store.loadOutput(context.sessionID, id: id).text)
        let commands = try #require(manifest["commands"] as? [[String: Any]])
        #expect(commands[0]["complete"] as? Bool == false)
        #expect(commands[1]["status"] as? String == "not_started")
        #expect(!FileManager.default.fileExists(atPath: fixture.directory.appending(path: "forbidden").path))
    }

    private func makeContext(
        _ fixture: ControllerFixture, limits: OutputLimits = OutputLimits()
    ) async throws -> NativeContext {
        let store = try await SQLiteSessionStore.open(directory: fixture.directory.appending(path: "sessions"))
        let session = try await store.create(
            workspace: fixture.directory.path,
            context: SessionContext(prompt: "test", model: Models.codex.ref, effort: nil))
        return NativeContext(store: store, sessionID: session.id, workingDirectory: fixture.directory, limits: limits)
            .withExecution([.bash(workingDirectory: fixture.directory)])
    }

    private func decode(_ text: String) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }
}

extension ContextBatchTests {
    @Test func deadlineStopsLaterCommandsWithAnExplicitTimeoutRecord() async throws {
        let fixture = ControllerFixture()
        let context = try await makeContext(fixture)
        let tool = try #require(context.tools.first { $0.name == "batch_execute" })
        let result = try await tool.function(
            #"{"commands":[{"command":"sleep 2"},{"command":"touch forbidden"}],"timeout_seconds":0.1}"#)
        let id = try #require(try decode(result)["output_id"] as? String)
        let manifest = try decode(try await context.store.loadOutput(context.sessionID, id: id).text)
        let commands = try #require(manifest["commands"] as? [[String: Any]])
        #expect(commands[0]["timed_out"] as? Bool == true)
        #expect(commands[1]["status"] as? String == "not_started")
        #expect(!FileManager.default.fileExists(atPath: fixture.directory.appending(path: "forbidden").path))
    }

    @Test func cancellationNeverRunsTheNextCommandOrConvertsToSuccess() async throws {
        let fixture = ControllerFixture()
        let context = try await makeContext(fixture)
        let tool = try #require(context.tools.first { $0.name == "batch_execute" })
        let task = Task {
            try await tool.function(
                #"{"commands":[{"command":"touch started; sleep 1; touch escaped"},{"command":"touch forbidden"}]}"#)
        }
        let started = fixture.directory.appending(path: "started")
        for _ in 0..<100 {
            if FileManager.default.fileExists(atPath: started.path) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(FileManager.default.fileExists(atPath: started.path))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        try await Task.sleep(for: .milliseconds(1100))
        #expect(!FileManager.default.fileExists(atPath: fixture.directory.appending(path: "escaped").path))
        #expect(!FileManager.default.fileExists(atPath: fixture.directory.appending(path: "forbidden").path))
    }
}
