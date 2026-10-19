import Foundation
import ModelKit
import OpenRouter
import Testing

@testable import TagKit

/// A fresh temporary directory, removed when the value is deinitialised.
final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appending(path: "TagKitTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    func write(_ contents: String, to path: String) throws {
        let file = url.appending(path: path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: file, atomically: true, encoding: .utf8)
    }

    func read(_ path: String) throws -> String {
        try String(contentsOf: url.appending(path: path), encoding: .utf8)
    }
}

struct FileToolsTests {
    let directory: TemporaryDirectory

    init() throws {
        directory = try TemporaryDirectory()
    }

    func run(_ tool: (URL) -> ToolDefinition, _ input: String) async throws -> String {
        try await tool(directory.url).function(input)
    }

    @Test func readFileReturnsContents() async throws {
        try directory.write("hello", to: "a.txt")
        #expect(try await run(ToolDefinition.readFile, #"{"path":"a.txt"}"#) == "hello")
    }

    @Test func readFileAcceptsAbsolutePaths() async throws {
        try directory.write("hello", to: "a.txt")
        let path = directory.url.appending(path: "a.txt").path(percentEncoded: false)
        #expect(try await run(ToolDefinition.readFile, #"{"path":"\#(path)"}"#) == "hello")
    }

    @Test func readFileRejectsMissingPath() async throws {
        await #expect(throws: ToolError.self) {
            try await run(ToolDefinition.readFile, "{}")
        }
    }

    @Test func listFilesListsRecursivelyAndSkipsHiddenEntries() async throws {
        try directory.write("", to: "b.txt")
        try directory.write("", to: "dir/c.txt")
        try directory.write("", to: ".git/config")
        try directory.write("", to: ".hidden")
        #expect(try await run(ToolDefinition.listFiles, "") == #"["b.txt","dir\/","dir\/c.txt"]"#)
        #expect(try await run(ToolDefinition.listFiles, #"{"path":"dir"}"#) == #"["c.txt"]"#)
    }

    @Test func listFilesRejectsFiles() async throws {
        try directory.write("", to: "b.txt")
        await #expect(throws: ToolError("not a directory: b.txt")) {
            try await run(ToolDefinition.listFiles, #"{"path":"b.txt"}"#)
        }
    }

    @Test func editFileReplacesTheSingleMatch() async throws {
        try directory.write("let x = 1\nlet y = 2\n", to: "main.swift")
        let input = #"{"path":"main.swift","old_str":"x = 1","new_str":"x = 3"}"#
        #expect(try await run(ToolDefinition.editFile, input) == "OK")
        #expect(try directory.read("main.swift") == "let x = 3\nlet y = 2\n")
    }

    @Test func editFileCreatesMissingFilesAndDirectories() async throws {
        let input = #"{"path":"new/dir/file.txt","old_str":"","new_str":"content"}"#
        #expect(try await run(ToolDefinition.editFile, input) == "Successfully created file new/dir/file.txt")
        #expect(try directory.read("new/dir/file.txt") == "content")
    }

    @Test(arguments: [
        (#"{"path":"","old_str":"a","new_str":"b"}"#, "invalid input parameters"),
        (#"{"path":"f.txt","old_str":"a","new_str":"a"}"#, "invalid input parameters"),
        (#"{"path":"missing.txt","old_str":"a","new_str":"b"}"#, "file not found"),
        (#"{"path":"f.txt","old_str":"","new_str":"b"}"#, "must not be empty"),
        (#"{"path":"f.txt","old_str":"zzz","new_str":"b"}"#, "not found in file"),
        (#"{"path":"f.txt","old_str":"a","new_str":"b"}"#, "matches 2 times"),
        (#"{"path":"f.txt"}"#, "invalid input"),
    ])
    func editFileRejects(input: String, message: String) async throws {
        try directory.write("a a", to: "f.txt")
        let error = await #expect(throws: ToolError.self) {
            try await run(ToolDefinition.editFile, input)
        }
        #expect(error?.message.contains(message) == true)
        #expect(try directory.read("f.txt") == "a a")
    }

    @Test func builtInToolsHaveDistinctNamesAndSchemas() {
        let tools = ToolDefinition.builtIn(workingDirectory: directory.url)
        #expect(tools.map(\.name) == ["read_file", "list_files", "edit_file", "bash", "code_search"])
        for tool in tools {
            #expect(tool.parameters["type"] == "object")
            #expect(tool.spec.name == tool.name)
        }
    }
}
