import Foundation
import Testing

@testable import TagKit

struct ProtectedPathsTests {
    private let root = FileManager.default.temporaryDirectory.appending(path: "tag-tests-\(UUID().uuidString)")
    private var config: URL { root.appending(path: "config", directoryHint: .isDirectory) }
    private var project: URL { root.appending(path: "project", directoryHint: .isDirectory) }

    private func prepare() throws -> ProtectedPaths {
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try "{\"apiKeys\":{}}".write(to: config.appending(path: "credentials.json"), atomically: true, encoding: .utf8)
        return ProtectedPaths(directories: [config])
    }

    @Test func theFileToolsRefuseTheConfigDirectoryAlsoThroughLinksAndDotDot() throws {
        let protected = try prepare()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createSymbolicLink(at: project.appending(path: "link"), withDestinationURL: config)
        let tools = FileTools(workingDirectory: project, protected: protected)

        #expect(throws: ToolError.self) { try tools.read(config.appending(path: "credentials.json").path) }
        #expect(throws: ToolError.self) { try tools.read("../config/credentials.json") }
        #expect(throws: ToolError.self) { try tools.read("link/credentials.json") }
        #expect(throws: ToolError.self) { try tools.list("../config") }
        #expect(throws: ToolError.self) { try tools.edit("../config/credentials.json", replacing: "", with: "x") }

        try "ok".write(to: project.appending(path: "a.txt"), atomically: true, encoding: .utf8)
        #expect(try tools.read("a.txt") == "ok")
        #expect(throws: Never.self) { try protected.check(root.appending(path: "configuration")) }
    }

    @Test func commandsNamingTheDirectoryAreRefusedHoweverItIsSpelled() throws {
        let home = URL(filePath: "/Users/me", directoryHint: .isDirectory)
        let directory = home.appending(path: ".config/tag", directoryHint: .isDirectory)
        #expect(
            ProtectedPaths.spellings(of: directory, home: home) == [
                "/Users/me/.config/tag", "~/.config/tag", "$HOME/.config/tag", "${HOME}/.config/tag", ".config/tag",
            ])
        #expect(ProtectedPaths.spellings(of: URL(filePath: "/opt/tag"), home: home) == ["/opt/tag"])

        let protected = try prepare()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: ToolError.self) { try protected.check(command: "cat \(config.path)/credentials.json") }
        #expect(throws: Never.self) { try protected.check(command: "cat credentials.json && ls") }
    }

    @Test func bashAndCodeSearchUseTheGuard() async throws {
        let protected = try prepare()
        defer { try? FileManager.default.removeItem(at: root) }
        let bash = ToolDefinition.bash(workingDirectory: project, protecting: protected)
        let search = ToolDefinition.codeSearch(workingDirectory: project, protecting: protected)
        await #expect(throws: ToolError.self) {
            try await bash.function(#"{"command":"cat \#(config.path)/credentials.json"}"#)
        }
        await #expect(throws: ToolError.self) {
            try await search.function(#"{"pattern":"apiKeys","path":"\#(config.path)"}"#)
        }
        let refusal = try? await bash.function(#"{"command":"cat \#(config.path)/x"}"#)
        #expect(refusal == nil)
    }
}
