import Foundation
import ModelKit
import SessionKit
import Testing

@testable import TagKit

@MainActor
struct NativeToolCaptureTests {
    @Test func nativeShellAndSearchRetainOverflowWithoutLosingStatus() async throws {
        let directory = try TemporaryDirectory()
        let bash = ToolDefinition.bash(workingDirectory: directory.url)
        let capture = try #require(bash.captureFunction)
        let outcome = try await capture(#"{"command":"printf ' error\\n'; exit 3"}"#)
        #expect(outcome.content == " error\n")
        #expect(outcome.exitCode == 3)
        #expect(outcome.failed)
        let lines = (1...100).map { "needle \($0)" }.joined(separator: "\n")
        try directory.write(lines, to: "lines.txt")
        let search = try #require(ToolDefinition.codeSearch(workingDirectory: directory.url).captureFunction)
        let found = try await search(#"{"pattern":"needle"}"#)
        #expect(found.content.contains("lines.txt:100:needle 100"))
        #expect(!found.failed)
    }

    @Test func boundedFileCaptureMarksPartialAndProtectsResolvedPaths() async throws {
        let directory = try TemporaryDirectory()
        try directory.write("猫\n猫\n猫\n", to: "file.txt")
        let files = FileTools(workingDirectory: directory.url)
        let outcome = try await files.captureRead("file.txt", byteLimit: 6)
        #expect(outcome.content == "猫\n")
        #expect(!outcome.complete)
        #expect(outcome.failed)
        let protected = directory.url.appending(path: "secret")
        try FileManager.default.createDirectory(at: protected, withIntermediateDirectories: true)
        try directory.write("private", to: "secret/key")
        try FileManager.default.createSymbolicLink(
            at: directory.url.appending(path: "link"), withDestinationURL: protected.appending(path: "key"))
        let guarded = FileTools(workingDirectory: directory.url, protected: ProtectedPaths(directories: [protected]))
        await #expect(throws: ToolError.self) { try await guarded.captureRead("link") }
    }

    @Test func incompleteSmallOutputIsRetainedAndClearlyLabelled() async throws {
        let fixture = ControllerFixture()
        let store = try await SQLiteSessionStore.open(directory: fixture.directory.appending(path: "sessions"))
        let session = try await store.create(
            workspace: fixture.directory.path,
            context: SessionContext(prompt: "test", model: Models.codex.ref, effort: nil))
        let context = NativeContext(store: store, sessionID: session.id, workingDirectory: fixture.directory)
        let outcome = ToolOutcome(content: "partial", failed: true, complete: false, exitCode: 143, timedOut: true)
        let admitted = try await context.admit(
            outcome, call: ToolCall(id: "partial", name: "bash", arguments: "{}"), budget: 1024)
        let reference = try #require(admitted.reference)
        #expect(!reference.complete)
        let json = try #require(try JSONSerialization.jsonObject(with: Data(admitted.content.utf8)) as? [String: Any])
        #expect(json["complete"] as? Bool == false)
        #expect(json["exit_code"] as? Int == 143)
        #expect(json["timed_out"] as? Bool == true)
    }
}
