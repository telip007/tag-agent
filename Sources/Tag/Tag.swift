import ArgumentParser
import Foundation
import TagKit

@main
struct Tag: AsyncParsableCommand {
    mutating func run() async throws {
        let workingDirectory = URL(filePath: FileManager.default.currentDirectoryPath, directoryHint: .isDirectory)
        let agent = try Agent(
            model: OpenRouterChatModel(),
            tools: ToolDefinition.builtIn(workingDirectory: workingDirectory),
        ) { readLine() }
        try await agent.run()
    }
}
