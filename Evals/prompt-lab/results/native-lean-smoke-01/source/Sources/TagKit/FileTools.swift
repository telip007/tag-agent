public import Foundation
import OpenRouter

// The three file tools from "How to build an agent": read_file, list_files and
// edit_file. See wiki/concepts/tools.md for where they differ from the Go
// originals.

extension ToolDefinition {
    /// `read_file`: returns the contents of a text file.
    public static func readFile(workingDirectory: URL, protecting protected: ProtectedPaths = .tagConfig) -> Self {
        Self(
            name: "read_file",
            description: """
                Read the contents of a given relative file path. Use this when you want to see what's inside a file. \
                Do not use this with directory names.
                """,
            parameters: [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "The relative path of a file in the working directory."]
                ],
                "required": ["path"],
            ],
            summary: "read a file",
        ) { json in
            struct Input: Decodable { var path: String }
            let input = try decodeInput(json, as: Input.self)
            return try FileTools(workingDirectory: workingDirectory, protected: protected).read(input.path)
        }
    }

    /// `list_files`: lists files and directories below a path, recursively.
    public static func listFiles(workingDirectory: URL, protecting protected: ProtectedPaths = .tagConfig) -> Self {
        Self(
            name: "list_files",
            description: """
                List files and directories at a given path. If no path is provided, lists files in the current \
                directory.
                """,
            parameters: [
                "type": "object",
                "properties": [
                    "path": [
                        "type": "string",
                        "description":
                            "Optional relative path to list files from. Defaults to current directory if not provided.",
                    ]
                ],
            ],
            summary: "list a folder, recursively",
        ) { json in
            struct Input: Decodable { var path: String? }
            let input = try decodeInput(json, as: Input.self)
            return try FileTools(workingDirectory: workingDirectory, protected: protected).list(input.path ?? ".")
        }
    }

    /// `edit_file`: replaces one exact occurrence of a string, or creates a file.
    public static func editFile(workingDirectory: URL, protecting protected: ProtectedPaths = .tagConfig) -> Self {
        Self(
            name: "edit_file",
            description: """
                Make edits to a text file. Replaces 'old_str' with 'new_str' in the given file. 'old_str' and \
                'new_str' MUST be different from each other. If the file specified with path doesn't exist, it will \
                be created.
                """,
            parameters: [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "The path to the file"],
                    "old_str": [
                        "type": "string",
                        "description": "Text to search for - must match exactly and must only have one match exactly",
                    ],
                    "new_str": ["type": "string", "description": "Text to replace old_str with"],
                ],
                "required": ["path", "old_str", "new_str"],
            ],
            summary: "replace one exact, unique snippet in a file, or create a file",
            guidelines: [
                "To edit a file, read it first, then give edit_file a snippet long enough to be unique."
            ],
        ) { json in
            struct Input: Decodable {
                var path: String
                var oldStr: String
                var newStr: String
                enum CodingKeys: String, CodingKey {
                    case path
                    case oldStr = "old_str"
                    case newStr = "new_str"
                }
            }
            let input = try decodeInput(json, as: Input.self)
            return try FileTools(workingDirectory: workingDirectory, protected: protected)
                .edit(input.path, replacing: input.oldStr, with: input.newStr)
        }
    }
}

/// The file operations behind the file tools, relative to a working directory.
struct FileTools {
    let workingDirectory: URL
    /// Directories the tools refuse, such as Tag's own config directory.
    var protected = ProtectedPaths.nothing

    private var fileManager: FileManager { .default }

    /// The file `path` names, relative to the working directory.
    ///
    /// - Throws: A ``ToolError`` when it is protected.
    func url(for path: String) throws -> URL {
        let url = path.hasPrefix("/") ? URL(filePath: path) : workingDirectory.appending(path: path)
        try protected.check(url)
        return url
    }

    func read(_ path: String) throws -> String {
        try String(contentsOf: try url(for: path), encoding: .utf8)
    }

    /// Lists everything below `path` as relative paths, directories with a
    /// trailing `/`. Hidden files and directories (`.git`, `.build`) are
    /// skipped so the listing stays small enough for the model's context.
    func list(_ path: String) throws -> String {
        let url = try url(for: path)
        guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
            let enumerator = fileManager.enumerator(atPath: url.path(percentEncoded: false))
        else {
            throw ToolError("not a directory: \(path)")
        }
        var entries: [String] = []
        while let entry = enumerator.nextObject() as? String {
            let isDirectory = enumerator.fileAttributes?[.type] as? FileAttributeType == .typeDirectory
            if entry.split(separator: "/").last?.hasPrefix(".") == true {
                if isDirectory { enumerator.skipDescendants() }
                continue
            }
            entries.append(isDirectory ? entry + "/" : entry)
        }
        guard let json = String(bytes: try JSONEncoder().encode(entries.sorted()), encoding: .utf8) else {
            throw ToolError("could not encode the listing of \(path)")
        }
        return json
    }

    /// Replaces the single occurrence of `oldString` with `newString`, or
    /// creates the file with `newString` if it doesn't exist and `oldString`
    /// is empty.
    func edit(_ path: String, replacing oldString: String, with newString: String) throws -> String {
        guard !path.isEmpty, oldString != newString else {
            throw ToolError("invalid input parameters: path must not be empty and old_str must differ from new_str")
        }
        let url = try url(for: path)
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else {
            guard oldString.isEmpty else {
                throw ToolError("file not found: \(path). To create it, pass an empty old_str.")
            }
            return try create(url, path: path, contents: newString)
        }
        guard !oldString.isEmpty else {
            throw ToolError("old_str must not be empty when editing an existing file")
        }
        let contents = try String(contentsOf: url, encoding: .utf8)
        let matches = contents.components(separatedBy: oldString).count - 1
        guard matches == 1 else {
            throw ToolError(
                matches == 0
                    ? "old_str not found in file"
                    : "old_str matches \(matches) times; include more context so it matches exactly once"
            )
        }
        let edited = contents.replacingOccurrences(of: oldString, with: newString)
        try edited.write(to: url, atomically: true, encoding: .utf8)
        return "OK"
    }

    private func create(_ url: URL, path: String, contents: String) throws -> String {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return "Successfully created file \(path)"
    }
}
