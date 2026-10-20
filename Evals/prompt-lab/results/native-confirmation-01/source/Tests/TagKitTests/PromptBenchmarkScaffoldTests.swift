import Foundation
import ModelKit
import Testing

@testable import TagKit

struct PromptBenchmarkScaffoldTests {
    @Test func leanPreservesRulesEnvironmentAndProjectInstructions() throws {
        let tools = ToolDefinition.builtIn(workingDirectory: SessionEnvironment.fake.workingDirectory)
        var environment = SessionEnvironment.fake
        environment.projectInstructions = "Preserve this project policy."
        let standard = SystemPrompt.render(tools: tools, environment: environment, model: "M")
        let lean = try BenchmarkPolicy.applying(nil, to: standard, tools: tools, scaffold: .lean)
        let standardRules = try #require(standard.range(of: "<rules>\n"))
        #expect(lean == "You are Tag, a coding agent.\n\n" + standard[standardRules.lowerBound...])
        #expect(!lean.contains("<tools>"))
        #expect(lean.contains("Preserve this project policy."))
        let changed = try BenchmarkPolicy.applying(["Core policy."], to: standard, tools: tools, scaffold: .lean)
        #expect(changed.contains("- Core policy."))
        for guideline in tools.flatMap(\.guidelines) {
            #expect(changed.contains("- \(guideline)"))
        }
    }

    @Test func leanRejectsUnexpectedStructureEvenForBaseline() {
        #expect(throws: BenchmarkFailure.self) {
            try BenchmarkPolicy.applying(nil, to: "Unexpected system text", scaffold: .lean)
        }
    }

    @Test @MainActor func leanForwardsEveryNativeAPIToolSchemaThroughTheAgent() async throws {
        let model = BenchmarkSchemaCapture()
        let tools = ToolDefinition.builtIn(workingDirectory: SessionEnvironment.fake.workingDirectory)
        let wrapper = BenchmarkModel(underlying: model, rules: nil, tools: tools, maxCalls: 1, scaffold: .lean)
        let entry = ScriptedModel([]).entry
        var supplied = false
        let agent = Agent(
            model: { ActiveModel(entry: entry, chatModel: wrapper) }, tools: tools, environment: .fake,
            output: { _ in },
            input: {
                guard !supplied else { return nil }
                supplied = true
                return .message("Answer this question")
            },
        )
        try await agent.run()
        #expect(model.tools == tools.map(\.spec))
        #expect(model.prompt == wrapper.prompt)
        #expect(wrapper.prompt.hasPrefix("You are Tag, a coding agent.\n\n<rules>"))
    }
}

private final class BenchmarkSchemaCapture: ChatModel {
    var tools: [ToolSpec] = []
    var prompt = ""

    func reply(
        to conversation: [Message], tools: [ToolSpec], options: ReplyOptions,
        onDelta: (ReplyDelta) -> Void,
    ) throws -> ModelReply {
        self.tools = tools
        if case .system(let text) = conversation.first { prompt = text }
        return ModelReply(message: AssistantMessage(text: "Done."))
    }
}
