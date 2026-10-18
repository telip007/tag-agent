import ArgumentParser
import Foundation
import Stipple
import TagKit

@main
struct Tag: AsyncParsableCommand {
    mutating func run() async throws {
        try await Self.chat()
    }

    /// Runs the chat UI until the user quits or the agent fails.
    @MainActor
    private static func chat() async throws {
        let workingDirectory = URL(filePath: FileManager.default.currentDirectoryPath, directoryHint: .isDirectory)
        let session = ChatSession()
        let agent = try await Agent(
            model: OpenRouterChatModel(),
            tools: ToolDefinition.builtIn(workingDirectory: workingDirectory),
            environment: SessionEnvironment.probe(workingDirectory: workingDirectory),
            output: session.handle,
            getUserMessage: session.nextMessage,
        )
        try await Stipple.run(ChatView(session: session, agent: agent), options: ChatView.renderOptions)
    }
}
