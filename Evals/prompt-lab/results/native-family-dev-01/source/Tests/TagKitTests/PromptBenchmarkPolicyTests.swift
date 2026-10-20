import Foundation
import ModelKit
import Testing

@testable import TagKit

struct PromptBenchmarkPolicyTests {
    @Test func baselinePreservesTheExactRenderedPrompt() throws {
        let prompt = SystemPrompt.render(tools: [], environment: .fake, model: "M")
        #expect(try BenchmarkPolicy.applying(nil, to: prompt) == prompt)
    }

    @Test func replacementPreservesToolsEnvironmentAndProjectRules() throws {
        let tool = ToolDefinition(
            name: "inspect", description: "inspect", parameters: [:],
            guidelines: ["Keep this tool rule."]
        ) { _ in "ok" }
        var environment = SessionEnvironment.fake
        environment.projectInstructions = "Leave project instructions intact."
        let prompt = SystemPrompt.render(tools: [tool], environment: environment, model: "M")
        let replacement = try BenchmarkPolicy.applying(["New policy."], to: prompt, tools: [tool])
        #expect(replacement.contains("- New policy.\n- Keep this tool rule."))
        #expect(!replacement.contains(SystemPrompt.rules[0]))
        #expect(replacement.contains("Leave project instructions intact."))
        #expect(
            replacement.components(separatedBy: "<environment>").last
                == prompt.components(separatedBy: "<environment>").last)
        #expect(replacement.components(separatedBy: "<rules>").first == prompt.components(separatedBy: "<rules>").first)
    }

    @Test func rejectsUnexpectedPromptStructure() {
        #expect(throws: BenchmarkFailure.self) {
            try BenchmarkPolicy.applying(["New policy."], to: "No rule section")
        }
    }

    @Test @MainActor func requestLimitStopsTheProductionLoop() async throws {
        let call = ModelKit.ToolCall(id: "one", name: "inspect", arguments: "{}")
        let scripted = ScriptedModel([AssistantMessage(toolCalls: [call]), AssistantMessage(text: "unexpected")])
        let tool = ToolDefinition(name: "inspect", description: "inspect", parameters: [:]) { _ in "evidence" }
        let recorder = BenchmarkModel(underlying: scripted, rules: nil, tools: [tool], maxCalls: 1)
        let tape = BenchmarkTape()
        var supplied = false
        let agent = Agent(
            model: { ActiveModel(entry: scripted.entry, chatModel: recorder) }, tools: [tool], environment: .fake,
            output: { tape.record($0) },
            input: {
                guard !supplied else { return nil }
                supplied = true
                return .message("Inspect once")
            },
        )
        try await agent.run()
        #expect(recorder.limitReached)
        #expect(recorder.attemptedCalls == 1)
        #expect(scripted.conversations.count == 1)
        #expect(tape.tools.count == 1)
        #expect(tape.failure != nil)
    }
}
