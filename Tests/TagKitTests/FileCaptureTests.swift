import Foundation
import Testing

@testable import TagKit

struct FileCaptureTests {
    @Test func listingsStopBeforeExceedingTheCaptureBudget() async throws {
        let directory = try TemporaryDirectory()
        for index in 1...200 { try directory.write("", to: "entry-\(index).txt") }
        let outcome = try await FileTools(workingDirectory: directory.url).captureList(".", byteLimit: 100)
        #expect(!outcome.complete)
        #expect(outcome.failed)
        #expect(outcome.content.utf8.count <= 100)
        let entries = try JSONDecoder().decode([String].self, from: Data(outcome.content.utf8))
        #expect(!entries.isEmpty)
        #expect(entries.count < 200)
    }

    @Test func nativeListingOmitsProtectedDescendantsAndHiddenEntries() async throws {
        let directory = try TemporaryDirectory()
        try directory.write("", to: "public.txt")
        try directory.write("", to: ".hidden.txt")
        try FileManager.default.createDirectory(
            at: directory.url.appending(path: "protected"), withIntermediateDirectories: false)
        try directory.write("secret", to: "protected/key")
        let tool = ToolDefinition.listFiles(
            workingDirectory: directory.url,
            protecting: ProtectedPaths(directories: [directory.url.appending(path: "protected")]))
        let capture = try #require(tool.captureFunction)
        let outcome = try await capture("{}")
        #expect(outcome.complete)
        let entries = try JSONDecoder().decode([String].self, from: Data(outcome.content.utf8))
        #expect(entries == ["public.txt"])
    }
}

extension FileCaptureTests {
    @Test func captureAndPreviewPreserveALeadingUTF8BOM() async throws {
        let directory = try TemporaryDirectory()
        try Data([0xEF, 0xBB, 0xBF, 0x61]).write(to: directory.url.appending(path: "bom"))
        let captured = try await FileTools(workingDirectory: directory.url).captureRead("bom")
        #expect(captured.content == "\u{FEFF}a")
        #expect(captured.content.utf8.count == 4)
        #expect(ContextText.prefix("\u{FEFF}a", bytes: 4) == "\u{FEFF}a")
        #expect(ContextText.suffix("x\u{FEFF}a", bytes: 4) == "\u{FEFF}a")
    }
}

extension FileCaptureTests {
    @Test(arguments: [[UInt8](arrayLiteral: 0xE0, 0x80), [0xED, 0xA0], [0xF0, 0x80], [0xF4, 0xBF]])
    func knownInvalidUTF8PrefixesCannotBeSilentlyDiscarded(bytes: [UInt8]) throws {
        #expect(throws: ToolError.self) { try CaptureText.decode(Data(bytes), complete: false) }
    }
}
