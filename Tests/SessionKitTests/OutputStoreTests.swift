import Foundation
import Testing

@testable import SessionKit

struct OutputStoreTests {
    @Test func reopeningPreservesExactEvidenceAndProvenance() async throws {
        let fixture = SessionStoreFixture()
        let store = try await fixture.open()
        let session = try await store.create(workspace: "/work/project", context: fixture.context)
        let text = "first\n猫\u{0}last\n"
        let reference = try await store.saveOutput(
            session.id, text: text, source: "test log", callID: "call-1", complete: false)
        let reopened = try await fixture.open()
        let page = try await reopened.readOutput(session.id, id: reference.id, offset: 0, limit: 100)
        #expect(page.text == text)
        #expect(page.nextOffset == nil)
        #expect(page.reference.source == "test log")
        #expect(page.reference.callID == "call-1")
        #expect(!page.reference.complete)
        #expect(page.reference.byteCount == 15)
        #expect(page.reference.sha256 == "79bcc57247b305d22068d6e5f2cd7caba3b970b63ddc69227e3229725c95ad87")
    }

    @Test func referencesCannotCrossSessionsOrBecomePaths() async throws {
        let fixture = SessionStoreFixture()
        let store = try await fixture.open()
        let first = try await store.create(workspace: "/work/first", context: fixture.context)
        let second = try await store.create(workspace: "/work/second", context: fixture.context)
        let reference = try await store.saveOutput(first.id, text: "private", source: "log")
        await #expect(throws: OutputError.notFound) {
            try await store.readOutput(second.id, id: reference.id, offset: 0, limit: 100)
        }
        await #expect(throws: OutputError.notFound) {
            try await store.readOutput(first.id, id: "../../sessions.sqlite", offset: 0, limit: 100)
        }
    }

    @Test func bytePaginationPreservesUnicodeAndRejectsInvalidRanges() async throws {
        let fixture = SessionStoreFixture()
        let store = try await fixture.open()
        let session = try await store.create(workspace: "/work/project", context: fixture.context)
        let reference = try await store.saveOutput(session.id, text: "ab猫cd", source: "file")
        let first = try await store.readOutput(session.id, id: reference.id, offset: 0, limit: 4)
        #expect(first.text == "ab")
        #expect(first.nextOffset == 2)
        let second = try await store.readOutput(session.id, id: reference.id, offset: 2, limit: 4)
        #expect(second.text == "猫c")
        #expect(second.nextOffset == 6)
        let last = try await store.readOutput(session.id, id: reference.id, offset: 6, limit: 4)
        #expect(last.text == "d")
        #expect(last.nextOffset == nil)
        for offset in [-1, 3, 8] {
            await #expect(throws: OutputError.invalidRange) {
                try await store.readOutput(session.id, id: reference.id, offset: offset, limit: 4)
            }
        }
        await #expect(throws: OutputError.invalidRange) {
            try await store.readOutput(session.id, id: reference.id, offset: 2, limit: 1)
        }
    }

    @Test func quotasRejectWholeWritesWithoutLosingEarlierEvidence() async throws {
        let fixture = SessionStoreFixture()
        let store = try await fixture.open()
        let session = try await store.create(workspace: "/work/project", context: fixture.context)
        let limits = OutputLimits(perOutput: 8, perSession: 10)
        let first = try await store.saveOutput(session.id, text: "123456", source: "first", limits: limits)
        await #expect(throws: OutputError.quotaExceeded) {
            try await store.saveOutput(session.id, text: "12345", source: "second", limits: limits)
        }
        await #expect(throws: OutputError.quotaExceeded) {
            try await store.saveOutput(session.id, text: "123456789", source: "too large", limits: limits)
        }
        let page = try await store.readOutput(session.id, id: first.id, offset: 0, limit: 100)
        #expect(page.text == "123456")
        let statistics = try await store.outputStatistics(session.id)
        #expect(statistics.outputCount == 1)
        #expect(statistics.storedBytes == 6)
    }
}
