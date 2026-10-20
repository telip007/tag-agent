import Foundation
import ModelKit
import SessionKit
import Testing

@testable import TagKit

@MainActor
struct SessionReadAccessTests {
    @Test func aReferenceLookupCannotFollowTheUserIntoAnotherDestination() async throws {
        let fixture = ControllerFixture()
        let controller = try await fixture.controller()
        try await controller.open(.new)
        let active = try #require(controller.active)
        let source = try await sourceSession(controller, context: active.context, text: "hold evidence")
        let reads = PausedSessionReads(base: controller.store, heldQuery: "hold")
        let flow = SessionFlow(controller: controller, read: reads)
        let lookup = Task { try await flow.reference(source.id, query: "hold") }
        try await waitFor(reads, key: "reference")
        try await controller.newSession()
        await reads.release("reference")
        await #expect(throws: (any Error).self) { try await lookup.value }
        #expect(flow.referencePreview == nil)
        #expect(controller.draft.references.isEmpty)
        try await controller.close()
    }

    @Test func aDebouncedNewQueryInvalidatesAnOlderInFlightResultImmediately() async throws {
        let fixture = ControllerFixture()
        let controller = try await fixture.controller()
        try await controller.open(.new)
        let active = try #require(controller.active)
        _ = try await sourceSession(controller, context: active.context, text: "old evidence")
        let reads = PausedSessionReads(base: controller.store, heldQuery: "old")
        let flow = SessionFlow(controller: controller, read: reads)
        flow.debounceDuration = .seconds(30)
        await flow.open()
        let initial = flow.rows.map(\.id)
        let lookup = Task { await flow.search("old") }
        try await waitFor(reads, key: "list")
        flow.type("future")
        await reads.release("list")
        await lookup.value
        #expect(flow.query == "oldfuture")
        #expect(flow.rows.map(\.id) == initial)
        #expect(flow.isLoading)
        flow.close()
        try await controller.close()
    }

    @Test func aCancelledPreviewCannotReplaceTheNewHighlight() async throws {
        let fixture = ControllerFixture()
        let controller = try await fixture.controller()
        try await controller.open(.new)
        let active = try #require(controller.active)
        let first = try await sourceSession(controller, context: active.context, text: "first evidence")
        let second = try await sourceSession(controller, context: active.context, text: "second evidence")
        let reads = PausedSessionReads(base: controller.store, heldSource: first.id)
        let flow = SessionFlow(controller: controller, read: reads)
        await flow.open()
        flow.highlight(first.id)
        try await waitFor(reads, key: "preview")
        flow.highlight(second.id)
        for _ in 0..<200 where flow.preview.first?.source.sessionID != second.id {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(flow.preview.first?.source.sessionID == second.id)
        await reads.release("preview")
        for _ in 0..<10 { await Task.yield() }
        #expect(flow.preview.first?.text == "second evidence")
        flow.close()
        try await controller.close()
    }

    private func sourceSession(
        _ controller: SessionController, context: SessionContext, text: String
    ) async throws -> SessionSummary {
        let source = try await controller.store.create(workspace: controller.workspace, context: context)
        try await controller.store.rename(source.id, title: text)
        try await controller.store.append(
            source.id, event: .assistant(SessionAssistant(message: AssistantMessage(text: text), usage: nil)))
        return source
    }

    private func waitFor(_ reads: PausedSessionReads, key: String) async throws {
        for _ in 0..<200 where await !reads.hasStarted(key) { try await Task.sleep(for: .milliseconds(5)) }
        #expect(await reads.hasStarted(key))
    }
}

private actor PausedSessionReads: SessionReadAccess {
    let base: SQLiteSessionStore
    let heldQuery: String?
    let heldSource: UUID?
    private var waiters: [String: CheckedContinuation<Void, Never>] = [:]
    private var started: Set<String> = []

    init(base: SQLiteSessionStore, heldQuery: String? = nil, heldSource: UUID? = nil) {
        self.base = base
        self.heldQuery = heldQuery
        self.heldSource = heldSource
    }

    func list(workspace: String?, query: String, after: SessionCursor?, limit: Int) async throws -> [SessionSummary] {
        let result = try await base.list(workspace: workspace, query: query, after: after, limit: limit)
        if query == heldQuery { await pause("list") }
        return result
    }

    func search(_ id: UUID, query: String) async throws -> [SessionReference] {
        let result = try await base.search(id, query: query)
        if query == heldQuery { await pause("reference") }
        if id == heldSource { await pause("preview") }
        return result
    }

    func hasStarted(_ key: String) -> Bool { started.contains(key) }
    func release(_ key: String) { waiters.removeValue(forKey: key)?.resume() }

    private func pause(_ key: String) async {
        started.insert(key)
        await withCheckedContinuation { waiters[key] = $0 }
    }
}
