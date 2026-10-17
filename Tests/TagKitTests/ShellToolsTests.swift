import Foundation
import Testing

@testable import TagKit

struct ShellToolsTests {
    let directory: TemporaryDirectory

    init() throws {
        directory = try TemporaryDirectory()
    }

    func bash(_ command: String) async throws -> String {
        let input = try #require(String(bytes: JSONEncoder().encode(["command": command]), encoding: .utf8))
        return try await ToolDefinition.bash(workingDirectory: directory.url).function(input)
    }

    @Test func bashReturnsTrimmedOutputFromTheWorkingDirectory() async throws {
        try directory.write("", to: "marker.txt")
        #expect(try await bash("ls; echo") == "marker.txt")
    }

    @Test func bashMergesStandardErrorAndReportsFailures() async throws {
        #expect(
            try await bash("echo out; echo err >&2; exit 3") == "Command failed with exit code 3\nOutput: out\nerr\n")
    }

    @Test func bashGivesCommandsNoStandardInput() async throws {
        #expect(try await bash("cat").isEmpty)
    }

    @Test func bashRejectsHugeOutput() async throws {
        let error = await #expect(throws: ToolError.self) {
            try await bash("head -c 2000000 /dev/zero")
        }
        #expect(error?.message.contains("narrow the command") == true)
    }

    @Test func codeSearchPassesTheRipgrepArguments() async throws {
        // `echo` stands in for ripgrep and prints the arguments it was given.
        let tool = ToolDefinition.codeSearch(workingDirectory: directory.url, ripgrep: "echo")
        let output = try await tool.function(#"{"pattern":"-foo","file_type":"swift","path":"Sources"}"#)
        #expect(output == "--line-number --with-filename --color=never --ignore-case --type swift -- -foo Sources")
    }

    @Test func codeSearchReportsAMissingRipgrep() async throws {
        let tool = ToolDefinition.codeSearch(workingDirectory: directory.url, ripgrep: "tag-no-such-program")
        await #expect(throws: ToolError("tag-no-such-program is not installed")) {
            try await tool.function(#"{"pattern":"x"}"#)
        }
    }

    @Test func codeSearchRequiresAPattern() async throws {
        let tool = ToolDefinition.codeSearch(workingDirectory: directory.url, ripgrep: "echo")
        await #expect(throws: ToolError("pattern is required")) {
            try await tool.function(#"{"pattern":""}"#)
        }
    }

    @Test func ripgrepArgumentsDefaults() throws {
        let input = try ToolDefinition.decodeInput(
            #"{"pattern":"x","path":"","case_sensitive":true}"#, as: CodeSearchInput.self)
        #expect(input.ripgrepArguments == ["--line-number", "--with-filename", "--color=never", "--", "x", "."])
    }

    @Test func searchResults() throws {
        func result(_ status: Int32, _ output: String = "", _ errors: String = "") throws -> String {
            try ShellTools.searchResult(.init(status: status, output: output, errorOutput: errors))
        }
        #expect(try result(0, "a.swift:1:x\n") == "a.swift:1:x")
        #expect(try result(1) == "No matches found")
        #expect(throws: ToolError("search failed: regex parse error")) { try result(2, "", "regex parse error\n") }

        let lines = (1...60).map { "f:\($0):x" }.joined(separator: "\n")
        let truncated = try result(0, lines)
        #expect(truncated.split(separator: "\n").count == 51)
        #expect(truncated.hasSuffix("f:50:x\n... (showing first 50 of 60 matches)"))
    }

    static let ripgrepIsInstalled =
        ProcessInfo.processInfo.environment["PATH"]?.split(separator: ":").contains {
            FileManager.default.isExecutableFile(atPath: "\($0)/rg")
        } == true

    @Test(.enabled(if: ripgrepIsInstalled, "needs ripgrep (rg) on PATH"))
    func codeSearchWithRipgrep() async throws {
        try directory.write("let Answer = 42\n", to: "a.swift")
        try directory.write("answer\n", to: "b.txt")
        let tool = ToolDefinition.codeSearch(workingDirectory: directory.url)
        #expect(try await tool.function(#"{"pattern":"answer","file_type":"swift"}"#) == "./a.swift:1:let Answer = 42")
        #expect(try await tool.function(#"{"pattern":"nothing"}"#) == "No matches found")
    }
}
