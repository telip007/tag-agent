import Foundation
import ModelKit
import Testing

@testable import TagKit

/// Invoked only by the research supervisor with an explicit temporary job file.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["TAG_PROMPT_JOB"] != nil))
struct PromptBenchmarkLiveTests {
    @Test @MainActor func runJob() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["TAG_PROMPT_JOB"])
        let job = try JSONDecoder().decode(BenchmarkJob.self, from: Data(contentsOf: URL(filePath: path)))
        let provider = OpenCodeGoProvider(transport: BenchmarkTransport(maxTokens: job.maxTokens))
        let entries = try await provider.models()
        let entry = try #require(entries.first { $0.ref.model == job.model })
        #expect(entry.format == .chatCompletions)
        let tools = ToolDefinition.builtIn(workingDirectory: URL(filePath: job.directory))
        let recorder = BenchmarkModel(
            underlying: try await provider.chatModel(for: entry), rules: job.rules,
            tools: tools, maxCalls: job.maxCalls,
        )
        let tape = BenchmarkTape()
        var supplied = false
        let agent = Agent(
            model: { ActiveModel(entry: entry, chatModel: recorder) }, tools: tools,
            environment: await .probe(workingDirectory: URL(filePath: job.directory)),
            output: { tape.record($0) },
            input: {
                guard !supplied else { return nil }
                supplied = true
                return .message(job.task)
            },
        )
        try await agent.run()
        let outcome = BenchmarkOutcome(
            model: entry.ref.model, prompt: recorder.prompt, responses: recorder.responses,
            tools: tape.tools, final: tape.final, failure: tape.failure,
            requestLimitReached: recorder.limitReached, attemptedCalls: recorder.attemptedCalls,
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(outcome).write(to: URL(filePath: job.output), options: .atomic)
    }
}

@MainActor
final class BenchmarkTape {
    var tools: [BenchmarkToolEvent] = []
    var final = ""
    var failure: String?

    func record(_ event: AgentEvent) {
        switch event {
        case .reply(let text): final = text
        case .toolFinished(let name, let arguments, let output, let failed):
            tools.append(BenchmarkToolEvent(name: name, arguments: arguments, output: output, failed: failed))
        case .failure(let message, _): failure = message
        default: break
        }
    }
}
