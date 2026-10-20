import Foundation
import SessionKit
import Testing

@testable import ModelKit
@testable import TagKit

struct NativeContextEvaluationCase: Encodable {
    let name: String
    let inputBytes: Int
    let baselineBytes: Int
    let nativeBytes: Int
    let checks: [String: Bool]
    enum CodingKeys: String, CodingKey {
        case name, checks
        case inputBytes = "input_bytes"
        case baselineBytes = "baseline_bytes"
        case nativeBytes = "native_bytes"
    }
}

@MainActor
struct NativeContextEvaluationTests {
    @Test func deterministicNativeContextContracts() async throws {
        let results = [
            try await tailFailure(), try await wholeInput(), try await groupBudget(), try await projection(),
            try await scopeAndRange(), try await partialAndRecovery(),
        ]
        #expect(results.allSatisfy { $0.checks.values.allSatisfy { $0 } })
        if let path = ProcessInfo.processInfo.environment["TAG_CONTEXT_EVAL_REPORT"] {
            struct Report: Encodable {
                let fixtureRevision = 1
                let scope =
                    "Deterministic native contracts; no LLM solve-rate, provider-token, cache-cost or billing claim."
                let results: [NativeContextEvaluationCase]
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(Report(results: results)).write(to: URL(filePath: path), options: .atomic)
        }
    }

    func prepare() async throws -> (ControllerFixture, NativeContext) {
        let fixture = ControllerFixture()
        let store = try await SQLiteSessionStore.open(directory: fixture.directory.appending(path: "sessions"))
        let session = try await store.create(
            workspace: fixture.directory.path,
            context: SessionContext(prompt: "eval", model: Models.codex.ref, effort: nil))
        return (
            fixture,
            NativeContext(store: store, sessionID: session.id, workingDirectory: fixture.directory).withExecution([
                .bash(workingDirectory: fixture.directory)
            ])
        )
    }

    private func tailFailure() async throws -> NativeContextEvaluationCase {
        let (fixture, context) = try await prepare()
        defer { withExtendedLifetime(fixture) {} }
        let outcome = try await ProcessCapture.run(
            "awk", ["BEGIN { for(i=0;i<60000;i++) print \"case passed 00000000\"; print \"FAILED tail_7\"; exit 7 }"],
            in: fixture.directory)
        let admitted = try await context.admit(
            outcome, call: ToolCall(id: "tail", name: "bash", arguments: "{}"), budget: 1024)
        let reference = try #require(admitted.reference)
        let hits = try await context.store.searchOutputs(context.sessionID, query: "tail_7", outputID: reference.id)
        let first50 = outcome.content.split(separator: "\n").prefix(50).joined(separator: "\n")
        return NativeContextEvaluationCase(
            name: "large_tail_failure", inputBytes: outcome.content.utf8.count,
            baselineBytes: first50.utf8.count, nativeBytes: admitted.content.utf8.count,
            checks: [
                "capture_over_1mb": outcome.content.utf8.count > 1_000_000,
                "exit_7_preserved": outcome.exitCode == 7 && outcome.failed && outcome.complete,
                "first_50_misses_error": !first50.contains("tail_7"),
                "native_recovers_tail": hits.contains { $0.text.contains("FAILED tail_7") },
                "complete_reply_within_budget": admitted.content.utf8.count <= 1024,
            ])
    }

    private func wholeInput() async throws -> NativeContextEvaluationCase {
        let (fixture, context) = try await prepare()
        defer { withExtendedLifetime(fixture) {} }
        let source = (1...10_000).map(String.init).joined(separator: "\n") + "\n"
        let artifact = try await context.store.saveOutput(context.sessionID, text: source, source: "eval numbers")
        let command = "awk '{s += $1} END {print s}'"
        let sparse = source.split(separator: "\n").prefix(50).joined(separator: "\n") + "\n"
        let baseline = try await ProcessCapture.run(
            "bash", ["-c", command], in: fixture.directory, input: Data(sparse.utf8))
        let reply = try await context.invoke(
            ToolCall(
                id: "sum", name: "analyze_output",
                arguments: try ContextText.json([
                    "output_id": artifact.id, "command": command,
                ])), budget: 1024)
        let json = try #require(try JSONSerialization.jsonObject(with: Data(reply.content.utf8)) as? [String: Any])
        let id = try #require(json["output_id"] as? String)
        let full = try await context.store.loadOutput(context.sessionID, id: id)
        return NativeContextEvaluationCase(
            name: "whole_input_aggregate", inputBytes: source.utf8.count,
            baselineBytes: sparse.utf8.count, nativeBytes: reply.content.utf8.count,
            checks: [
                "sparse_sum_is_1275": baseline.content == "1275\n", "whole_sum_is_50005000": full.text == "50005000\n",
                "complete_source": json["source_complete"] as? Bool == true,
                "reply_within_budget": reply.content.utf8.count <= 1024,
            ])
    }
}
