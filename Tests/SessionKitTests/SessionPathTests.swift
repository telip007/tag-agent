import Foundation
import Testing

@testable import SessionKit

struct SessionPathTests {
    @Test func aDirectoryLinkDoesNotRedirectStorageOrChangeItsTarget() async throws {
        let fixture = SessionStoreFixture()
        let target = fixture.directory.appending(path: "unrelated")
        try FileManager.default.createDirectory(
            at: target, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        let link = fixture.directory.appending(path: "sessions-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        await #expect(throws: (any Error).self) { try await SQLiteSessionStore.open(directory: link) }
        #expect(try permissions(target) == 0o755)
        #expect(try FileManager.default.contentsOfDirectory(atPath: target.path).isEmpty)
    }

    @Test func aDatabaseLinkPreservesItsTargetBytesAndPermissions() async throws {
        let fixture = SessionStoreFixture()
        try SessionFiles.prepare(fixture.directory)
        let target = fixture.directory.appending(path: "unrelated.txt")
        try Data("preserve me".utf8).write(to: target)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: target.path)
        let link = fixture.directory.appending(path: "sessions.sqlite")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        await #expect(throws: (any Error).self) { try await fixture.open() }
        #expect(try Data(contentsOf: target) == Data("preserve me".utf8))
        #expect(try permissions(target) == 0o644)
    }

    @Test func aLockLinkIsRejectedBeforeChangingTheTargetOrClaimingOwnership() throws {
        let fixture = SessionStoreFixture()
        let locks = fixture.directory.appending(path: "locks")
        try SessionFiles.prepare(locks)
        let id = UUID()
        let target = fixture.directory.appending(path: "unrelated.txt")
        try Data("preserve me".utf8).write(to: target)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: target.path)
        let link = locks.appending(path: id.uuidString.lowercased() + ".lock")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        #expect(throws: (any Error).self) { try SessionOwnership(directory: fixture.directory, sessionID: id) }
        #expect(try permissions(target) == 0o644)
    }

    private func permissions(_ url: URL) throws -> Int? {
        try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
    }
}
