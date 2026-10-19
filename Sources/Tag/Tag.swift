import ArgumentParser
import Foundation
import ModelKit
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
        let credentials = CredentialStore()
        let settings = SettingsStore()
        let registry = ProviderRegistry(providers: [OpenRouterProvider(credentials: credentials)])
        guard let ref = settings.load().lastModel else {
            throw ValidationError("No model chosen yet.")
        }
        let entry = try await registry.entry(for: ref)
        let chatModel = try await registry.provider(ref.provider)?.chatModel(for: entry)
        guard let chatModel else {
            throw ValidationError("No provider for \(ref).")
        }
        let active = ActiveModel(entry: entry, chatModel: chatModel, effort: settings.load().effort(for: ref))
        let session = ChatSession()
        let agent = await Agent(
            model: { active },
            tools: ToolDefinition.builtIn(workingDirectory: workingDirectory),
            environment: SessionEnvironment.probe(workingDirectory: workingDirectory),
            output: session.handle,
            input: session.nextMessage,
        )
        try await Stipple.run(ChatView(session: session, agent: agent), options: ChatView.renderOptions)
    }
}
