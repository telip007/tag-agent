import Foundation
import GRDB
import ModelKit
import Testing

@testable import SessionKit

/// Each test uses a real isolated database, removed only after its connections close.
final class SessionStoreFixture {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    var context: SessionContext {
        SessionContext(prompt: "trusted", model: ModelRef(provider: .codex, model: "test"), effort: "high")
    }

    func open() async throws -> SQLiteSessionStore {
        try await SQLiteSessionStore.open(directory: directory)
    }
}

struct SessionStoreTests {
    @Test func reopeningRetainsExactOrderedEventsAndStableIdentity() async throws {
        let fixture = SessionStoreFixture()
        let store = try await fixture.open()
        let summary = try await store.create(workspace: "/work/project", context: fixture.context)
        let input = PendingInput(text: "hello", references: [])
        try await store.accept(summary.id, input: input)
        try await store.consume(
            summary.id, inputID: input.id,
            user: SessionUser(raw: "hello", message: "dated hello", date: "2026-10-20", references: []))
        try await store.append(
            summary.id,
            event: .assistant(
                SessionAssistant(
                    message: AssistantMessage(text: "saved"),
                    usage: Usage(inputTokens: 3, outputTokens: 2, cost: 0.25))))

        let reopened = try await fixture.open()
        let entries = try await reopened.entries(summary.id)
        #expect(entries.map(\.sequence) == [0, 1, 2])
        #expect(
            entries.last?.event
                == .assistant(
                    SessionAssistant(
                        message: AssistantMessage(text: "saved"),
                        usage: Usage(inputTokens: 3, outputTokens: 2, cost: 0.25))))
        let restored = try await reopened.summary(summary.id)
        #expect(restored.providerSessionID == summary.providerSessionID)
        #expect(restored.cost == 0.25)
        #expect(restored.contextTokens == 5)
        #expect(restored.lastDate == "2026-10-20")
        #expect(try await reopened.pending(summary.id).isEmpty)
    }

    @Test func consumingAnInputIsAtomicAndCannotDuplicateIt() async throws {
        let fixture = SessionStoreFixture()
        let store = try await fixture.open()
        let session = try await store.create(workspace: "/work/project", context: fixture.context)
        let input = PendingInput(text: "queued", references: [])
        try await store.accept(session.id, input: input)
        let user = SessionUser(raw: "queued", message: "queued", date: "2026-10-20", references: [])
        try await store.consume(session.id, inputID: input.id, user: user)
        await #expect(throws: SessionError.missingInput) {
            try await store.consume(session.id, inputID: input.id, user: user)
        }
        #expect(try await store.entries(session.id).count == 2)
    }

    @Test func concurrentAppendsDoNotLoseOrOverwriteEntries() async throws {
        let fixture = SessionStoreFixture()
        let first = try await fixture.open()
        let second = try await fixture.open()
        let session = try await first.create(workspace: "/work/project", context: fixture.context)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<20 {
                let store = index.isMultiple(of: 2) ? first : second
                group.addTask { try await store.append(session.id, event: .inferenceStarted) }
            }
            try await group.waitForAll()
        }
        #expect(try await first.entries(session.id).map(\.sequence) == Array(0...20).map(Int64.init))
    }
}
