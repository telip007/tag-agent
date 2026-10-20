import ModelKit
import Testing

@testable import TagKit

@MainActor
struct LiveCacheStatusTests {
    @Test(arguments: [nil, 0, 20] as [Int?])
    func updatesCacheMetricsBeforeToolsRun(cached: Int?) async throws {
        let calls = [toolCall("1", "echo", "{}")]
        let model = ScriptedModel([
            AssistantMessage(text: "prime"), AssistantMessage(toolCalls: calls), AssistantMessage(text: "done"),
        ])
        model.usage = Usage(inputTokens: 100, outputTokens: 1, cachedInputTokens: 80)
        let latest = cached.map { Usage(inputTokens: 100, outputTokens: 2, cachedInputTokens: $0) }
        let session = ChatSession()
        let terminal = Terminal(["first", "second"])
        var observed = false
        let agent = Agent(
            model: { model.active }, tools: [echo], environment: .fake,
            output: { event in
                session.handle(event)
                if event == .reply("prime") { model.usage = latest }
                if case .toolStarted = event {
                    observed = true
                    #expect(session.status?.usage == latest)
                }
            }, input: { terminal.inputs.isEmpty ? nil : terminal.inputs.removeFirst() })
        try await agent.run()
        #expect(observed)
    }

    @Test func clearsDisplayedMetricsBeforeANewModelsInference() async throws {
        let first = ScriptedModel([AssistantMessage(text: "prime")])
        first.usage = Usage(inputTokens: 100, outputTokens: 1, cachedInputTokens: 80)
        let second = ScriptedModel([AssistantMessage(text: "done")])
        second.entry.ref.model = "second"
        second.entry.name = "Second Model"
        var active = first.active
        let session = ChatSession()
        let terminal = Terminal(["one", "two"])
        let agent = Agent(
            model: { active }, environment: .fake,
            output: { event in
                session.handle(event)
                if event == .reply("prime") { active = second.active }
                if event == .thinking, active.entry.ref == second.entry.ref {
                    #expect(session.status?.usage == nil)
                    #expect(session.status?.model == second.active.description)
                }
            }, input: { terminal.inputs.isEmpty ? nil : terminal.inputs.removeFirst() })
        try await agent.run()
    }
}

@MainActor
struct LiveCacheTrayTests {
    @Test func metricsUpdatesKeepConsecutiveToolRepliesInOneTray() async throws {
        let model = ScriptedModel([
            AssistantMessage(toolCalls: [toolCall("1", "echo", "{}")]),
            AssistantMessage(toolCalls: [toolCall("2", "echo", "{}")]),
            AssistantMessage(text: "done"),
        ])
        let session = ChatSession()
        let terminal = Terminal(["go"])
        let agent = Agent(
            model: { model.active }, tools: [echo], environment: .fake, output: session.handle,
            input: { terminal.inputs.isEmpty ? nil : terminal.inputs.removeFirst() })
        try await agent.run()
        let trays = session.blocks.compactMap { block -> [ToolRun]? in
            if case .tools(let runs) = block.content { runs } else { nil }
        }
        #expect(trays.count == 1)
        #expect(trays.first?.count == 2)
    }
}
