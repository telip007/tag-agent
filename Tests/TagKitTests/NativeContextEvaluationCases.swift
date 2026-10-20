import Foundation
import SessionKit
import Testing

@testable import ModelKit
@testable import TagKit

extension NativeContextEvaluationTests {
    func groupBudget() async throws -> NativeContextEvaluationCase {
        let (fixture, context) = try await prepare()
        defer { withExtendedLifetime(fixture) {} }
        let text = String(repeating: "large", count: 2400)
        let tool = ToolDefinition(name: "fixture", description: "fixture", parameters: [:]) { _ in text }
        let calls = (1...5).map { ToolCall(id: "c\($0)", name: "fixture", arguments: "{}") }
        let model = ScriptedModel([AssistantMessage(toolCalls: calls), AssistantMessage(text: "done")])
        let terminal = Terminal(["run"])
        let agent = Agent(
            model: { model.active }, tools: [tool], environment: .fake, context: context, output: terminal.record,
            input: { terminal.inputs.isEmpty ? nil : terminal.inputs.removeFirst() })
        try await agent.run()
        let outputs = try #require(model.conversations.last).compactMap { message -> String? in
            if case .tool(_, _, let text) = message { return text }
            return nil
        }
        let bytes = outputs.reduce(0) { $0 + $1.utf8.count }
        return NativeContextEvaluationCase(
            name: "shared_group_budget", inputBytes: 60_000, baselineBytes: 60_000,
            nativeBytes: bytes,
            checks: [
                "five_results": outputs.count == 5, "group_within_32768": bytes <= 32_768,
                "five_exact_artifacts": try await context.store.outputStatistics(context.sessionID).outputCount == 5,
            ])
    }

    func projection() async throws -> NativeContextEvaluationCase {
        let (fixture, context) = try await prepare()
        defer { withExtendedLifetime(fixture) {} }
        let user = SessionUser(
            raw: "keep user constraint", message: "keep user constraint", date: "date", references: [])
        try await context.store.append(context.sessionID, event: .user(user))
        for index in 1...12 {
            try await context.store.append(
                context.sessionID,
                event: .assistant(
                    SessionAssistant(
                        message: AssistantMessage(text: String(repeating: "record \(index) ", count: 300)), usage: nil))
            )
        }
        let full = try await context.store.load(context.sessionID)
        _ = try await context.store.compactContext(context.sessionID)
        let model = ScriptedModel([])
        let state = ConversationState(
            active: model.active, prompt: { $0.name }, snapshot: try await context.store.load(context.sessionID))
        let before = try ContextText.json(AnthropicChatModel.messages(state.conversation)).utf8.count
        let after = try ContextText.json(AnthropicChatModel.messages(state.requestConversation)).utf8.count
        return NativeContextEvaluationCase(
            name: "explicit_request_projection", inputBytes: before, baselineBytes: before,
            nativeBytes: after,
            checks: [
                "request_json_smaller": after < before,
                "user_constraint_pinned": state.requestConversation.contains(.user(user.message)),
                "canonical_events_unchanged": Array(
                    try await context.store.entries(context.sessionID).prefix(full.entries.count)) == full.entries,
            ])
    }

    func scopeAndRange() async throws -> NativeContextEvaluationCase {
        let (fixture, context) = try await prepare()
        defer { withExtendedLifetime(fixture) {} }
        let source = try await context.store.saveOutput(context.sessionID, text: "ab猫\u{0}end", source: "unicode")
        let first = try await context.store.readOutput(context.sessionID, id: source.id, offset: 0, limit: 4)
        let next = try await context.store.readOutput(context.sessionID, id: source.id, offset: 2, limit: 4)
        let other = try await context.store.create(
            workspace: "/other", context: SessionContext(prompt: "eval", model: Models.codex.ref, effort: nil))
        var rejected = false
        do { _ = try await context.store.readOutput(other.id, id: source.id, offset: 0, limit: 4) } catch OutputError
            .notFound
        { rejected = true }
        return NativeContextEvaluationCase(
            name: "unicode_and_scope", inputBytes: 9, baselineBytes: 9,
            nativeBytes: first.text.utf8.count + next.text.utf8.count,
            checks: [
                "scalar_boundary_preserved": first.text == "ab" && first.nextOffset == 2,
                "nul_preserved": next.text == "猫\u{0}" && next.nextOffset == 6, "foreign_session_rejected": rejected,
            ])
    }
    func partialAndRecovery() async throws -> NativeContextEvaluationCase {
        let (fixture, context) = try await prepare()
        defer { withExtendedLifetime(fixture) {} }
        let output = try await context.store.saveOutput(
            context.sessionID, text: "partial evidence", source: "limited capture", complete: false)
        try await context.store.append(context.sessionID, event: .inferenceStarted)
        let before = try await context.store.entries(context.sessionID)
        let stats = try await context.store.contextStatistics(context.sessionID)
        let doctor = try await context.store.contextDoctor(context.sessionID)
        let read = try await context.store.readOutput(context.sessionID, id: output.id, offset: 0, limit: 100)
        return NativeContextEvaluationCase(
            name: "partial_capture_and_recovery", inputBytes: 16, baselineBytes: 16,
            nativeBytes: read.text.utf8.count,
            checks: [
                "incomplete_capture_not_upgraded": !output.complete && stats.incompleteCount == 1,
                "pending_work_distinguished_from_corruption": doctor.journalOK && doctor.needsRecovery,
                "doctor_does_not_replay_or_repair": try await context.store.entries(context.sessionID) == before,
                "partial_evidence_remains_exact": read.text == "partial evidence",
            ])
    }
}
