import Foundation
import ModelKit
import Testing

@testable import TagKit

@MainActor
struct CacheStatusTests {
    @Test func agentShowsTheLatestRequestsCacheCounts() async throws {
        let model = ScriptedModel([AssistantMessage(text: "Hi!")])
        model.usage = Usage(inputTokens: 100, outputTokens: 5, cachedInputTokens: 80, cacheWriteInputTokens: 10)
        let terminal = Terminal(["hello"])
        try await terminal.agent(model: model).run()
        #expect(terminal.statusLines.last?.contains("cache read 80 · write 10") == true)
        let line = try #require(
            terminal.events.compactMap { event -> StatusLine? in
                if case .status(let line) = event { line } else { nil }
            }.last)
        let session = ChatSession()
        session.handle(.status(line))
        let panel = SessionPanel(session: session, selection: makeSelection())
        #expect(plainText(panel, width: 30).contains("cache read 80 · write 10"))
    }

    @Test func clearingAndSwitchingModelsDiscardThePreviousCacheMetrics() {
        let model = ScriptedModel([])
        var state = ConversationState(active: model.active, prompt: { _ in "system" })
        let usage = Usage(inputTokens: 100, outputTokens: 5, cachedInputTokens: 80, cacheWriteInputTokens: 20)
        state.record(ModelReply(message: AssistantMessage(text: "one"), usage: usage))
        let session = state.sessionID
        state.reset()
        #expect(state.latestUsage == nil)
        #expect(state.contextTokens == 0)
        #expect(state.sessionID != session)
        state.record(ModelReply(message: AssistantMessage(text: "two"), usage: usage))
        model.entry.ref.model = "another-model"
        state.follow(model.active)
        #expect(state.latestUsage == nil)
    }

    @Test func unknownUsageClearsCacheCounts() async throws {
        let model = ScriptedModel([AssistantMessage(text: "one"), AssistantMessage(text: "two")])
        model.usage = Usage(inputTokens: 100, outputTokens: 5, cachedInputTokens: 80)
        let terminal = Terminal(["a", "b"])
        let agent = Agent(
            model: { model.active }, environment: .fake,
            output: { event in
                terminal.record(event)
                if event == .reply("one") { model.usage = nil }
            },
            input: { terminal.inputs.isEmpty ? nil : terminal.inputs.removeFirst() })
        try await agent.run()
        #expect(terminal.statusLines.contains { $0.contains("cache read 80") })
        #expect(terminal.statusLines.last?.contains("cache") == false)
    }
}

struct CacheStatusFormattingTests {
    @Test func distinguishesReportedZeroFromAnUnknownMetric() {
        let line = StatusLine(
            directory: URL(filePath: "/work"), model: ModelDescription(name: "m"),
            usage: Usage(inputTokens: 1, outputTokens: 2, cachedInputTokens: 0))
        #expect(line.cacheUsage == "cache read 0")
        #expect(line.text.contains("cache read 0"))
        var unknown = line
        unknown.usage = Usage(inputTokens: 1, outputTokens: 2)
        #expect(unknown.cacheUsage == nil)
    }
}
