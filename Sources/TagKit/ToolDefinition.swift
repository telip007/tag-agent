public import Foundation
public import OpenRouter

/// A function the model can call: its name, what it does, the JSON Schema of
/// its input, and the code that runs it.
public struct ToolDefinition: Sendable {
    /// The name the model uses to call the tool.
    public let name: String
    /// What the tool does and when to use it. The model reads this.
    public let description: String
    /// A JSON Schema object describing the tool's input.
    public let parameters: [String: JSONValue]
    let function: @Sendable (String) async throws -> String

    /// Creates a tool.
    ///
    /// - Parameters:
    ///   - name: The name the model uses to call the tool.
    ///   - description: What the tool does and when to use it.
    ///   - parameters: A JSON Schema object describing the input.
    ///   - function: Runs the tool on the raw JSON input and returns its output.
    ///     A thrown error is reported back to the model.
    public init(
        name: String,
        description: String,
        parameters: [String: JSONValue],
        function: @escaping @Sendable (String) async throws -> String,
    ) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.function = function
    }

    /// The tool as the OpenRouter API expects it.
    public var chatTool: ChatTool {
        .function(name: name, description: description, parameters: parameters)
    }
}

/// An error a tool reports back to the model.
public struct ToolError: LocalizedError, Equatable {
    /// What went wrong, in words the model can act on.
    public let message: String

    /// Creates an error with the given message.
    public init(_ message: String) {
        self.message = message
    }

    /// The message.
    public var errorDescription: String? { message }
}

extension ToolDefinition {
    /// Decodes a tool's JSON input. Models sometimes send an empty string
    /// instead of `{}` for a tool without required arguments.
    static func decodeInput<Input: Decodable>(_ json: String, as type: Input.Type = Input.self) throws -> Input {
        let json = json.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "{}" : json
        do {
            return try JSONDecoder().decode(type, from: Data(json.utf8))
        } catch {
            throw ToolError("invalid input: \(error.localizedDescription)")
        }
    }

    /// The tools Tag Agent ships with, resolving relative paths against
    /// `workingDirectory`.
    public static func builtIn(workingDirectory: URL) -> [Self] {
        [
            .readFile(workingDirectory: workingDirectory),
            .listFiles(workingDirectory: workingDirectory),
            .editFile(workingDirectory: workingDirectory),
            .bash(workingDirectory: workingDirectory),
            .codeSearch(workingDirectory: workingDirectory),
        ]
    }
}
