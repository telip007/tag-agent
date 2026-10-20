public import Foundation
import OpenRouter
import Subprocess

// The two tools from Geoffrey Huntley's "how-to-build-a-coding-agent" workshop
// that the original tutorial doesn't have: bash and code_search. See
// wiki/concepts/tools.md.

extension ToolDefinition {
    /// `bash`: runs a shell command in the working directory.
    public static func bash(workingDirectory: URL, protecting protected: ProtectedPaths = .tagConfig) -> Self {
        Self(
            name: "bash",
            description: "Execute a bash command and return its output. Use this to run shell commands.",
            parameters: [
                "type": "object",
                "properties": [
                    "command": ["type": "string", "description": "The bash command to execute."]
                ],
                "required": ["command"],
            ],
            summary: "run a command in the project folder",
            guidelines: [
                """
                Each bash call is a fresh shell in the project folder with no input: cd and export don't carry \
                over, so chain commands with && and use non-interactive flags.
                """
            ],
        ) { json in
            struct Input: Decodable { var command: String }
            let input = try decodeInput(json, as: Input.self)
            try protected.check(command: input.command)
            let result = try await ShellTools.run(
                "bash", ["-c", input.command], in: workingDirectory, mergingErrors: true,
            )
            return ShellTools.bashResult(result)
        }.capturing { json in
            struct Input: Decodable { var command: String }
            let input = try decodeInput(json, as: Input.self)
            try protected.check(command: input.command)
            return try await ShellTools.capture("bash", ["-c", input.command], in: workingDirectory)
        }.withContextExecutor(ContextCommandExecutor(directory: workingDirectory, protected: protected))
    }

    /// `code_search`: searches file contents with ripgrep.
    ///
    /// - Parameters:
    ///   - workingDirectory: Where relative search paths start.
    ///   - ripgrep: The ripgrep program, looked up on `PATH`.
    ///   - protected: Directories the search refuses.
    /// - Returns: The tool.
    public static func codeSearch(
        workingDirectory: URL, ripgrep: String = "rg", protecting protected: ProtectedPaths = .tagConfig,
    ) -> Self {
        Self(
            name: "code_search",
            description: """
                Search for code patterns using ripgrep (rg).

                Use this to find code patterns, function definitions, variable usage, or any text in the codebase.
                You can search by pattern, file type, or directory.
                """,
            parameters: codeSearchParameters,
            summary: "search file contents (ripgrep)",
            guidelines: ["Use code_search to find code instead of reading files one by one."],
        ) { json in
            let input = try decodeInput(json, as: CodeSearchInput.self)
            guard !input.pattern.isEmpty else {
                throw ToolError("pattern is required")
            }
            if let path = input.path {
                try protected.check(path.hasPrefix("/") ? URL(filePath: path) : workingDirectory.appending(path: path))
            }
            let result = try await ShellTools.run(ripgrep, input.ripgrepArguments, in: workingDirectory)
            return try ShellTools.searchResult(result)
        }.capturing { json in
            let input = try decodeInput(json, as: CodeSearchInput.self)
            guard !input.pattern.isEmpty else { throw ToolError("pattern is required") }
            if let path = input.path {
                try protected.check(path.hasPrefix("/") ? URL(filePath: path) : workingDirectory.appending(path: path))
            }
            var outcome = try await ShellTools.capture(ripgrep, input.ripgrepArguments, in: workingDirectory)
            // rg 1 means no match, provided execution and capture completed normally.
            if outcome.exitCode == 1, outcome.complete {
                outcome.failed = false
                outcome.content = "No matches found"
            }
            return outcome
        }
    }

    private static let codeSearchParameters: [String: JSONValue] = [
        "type": "object",
        "properties": [
            "pattern": ["type": "string", "description": "The search pattern or regex to look for"],
            "path": ["type": "string", "description": "Optional path to search in (file or directory)"],
            "file_type": [
                "type": "string",
                "description": "Optional file extension to limit search to (e.g., 'go', 'js', 'py')",
            ],
            "case_sensitive": [
                "type": "boolean",
                "description": "Whether the search should be case sensitive (default: false)",
            ],
        ],
        "required": ["pattern"],
    ]
}

struct CodeSearchInput: Decodable, Equatable {
    var pattern: String
    var path: String?
    var fileType: String?
    var caseSensitive: Bool?

    enum CodingKeys: String, CodingKey {
        case pattern
        case path
        case fileType = "file_type"
        case caseSensitive = "case_sensitive"
    }

    /// The arguments after `rg`. `--` keeps a pattern starting with `-` from
    /// being read as an option.
    var ripgrepArguments: [String] {
        var arguments = ["--line-number", "--with-filename", "--color=never"]
        if caseSensitive != true {
            arguments.append("--ignore-case")
        }
        if let fileType, !fileType.isEmpty {
            arguments += ["--type", fileType]
        }
        let path = path.flatMap { $0.isEmpty ? nil : $0 } ?? "."
        return arguments + ["--", pattern, path]
    }
}

/// How the shell tools turn a finished process into a tool result.
enum ShellTools {
    /// Search results beyond this many lines are cut off, to keep the
    /// model's context small.
    static let maxSearchLines = 50

    /// Runs a program and turns launch failures into errors the model can
    /// act on.
    static func run(
        _ program: String,
        _ arguments: [String],
        in directory: URL,
        mergingErrors: Bool = false,
    ) async throws -> ProcessRunner.Result {
        do {
            return try await ProcessRunner.run(program, arguments, in: directory, mergingErrors: mergingErrors)
        } catch ProcessRunner.Failure.notFound {
            throw ToolError("\(program) is not installed")
        } catch ProcessRunner.Failure.outputTooLarge {
            throw ToolError(
                "output is larger than \(ProcessRunner.outputLimit) bytes; narrow the command, e.g. with head or grep"
            )
        }
    }

    static func capture(_ program: String, _ arguments: [String], in directory: URL) async throws -> ToolOutcome {
        do { return try await ProcessCapture.run(program, arguments, in: directory) } catch let error as SubprocessError
            where error.code == .executableNotFound
        {
            throw ToolError("\(program) is not installed")
        }
    }

    /// A failing command is a normal result, not an error: its output is
    /// what the model needs to fix the command.
    static func bashResult(_ result: ProcessRunner.Result) -> String {
        guard result.status == 0 else {
            return "Command failed with exit code \(result.status)\nOutput: \(result.output)"
        }
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// ripgrep exits with 1 when nothing matched and 2 on errors.
    static func searchResult(_ result: ProcessRunner.Result) throws -> String {
        switch result.status {
        case 0:
            break
        case 1:
            return "No matches found"
        default:
            throw ToolError("search failed: \(result.errorOutput.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        let lines = result.output.trimmingCharacters(in: .whitespacesAndNewlines).split(
            separator: "\n",
            omittingEmptySubsequences: false,
        )
        guard lines.count > maxSearchLines else {
            return lines.joined(separator: "\n")
        }
        return lines.prefix(maxSearchLines).joined(separator: "\n")
            + "\n... (showing first \(maxSearchLines) of \(lines.count) matches)"
    }
}
