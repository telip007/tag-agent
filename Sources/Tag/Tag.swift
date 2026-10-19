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
        let registry = ProviderRegistry(providers: [OpenRouterProvider(credentials: credentials)])
        let selection = ModelSelection(registry: registry, credentials: credentials)
        if await !selection.restoreLastModel() {
            try await Stipple.run(OnboardingView(selection: selection), options: OnboardingView.renderOptions)
        }
        // Quitting the onboarding leaves no model.
        guard let first = selection.current else {
            return
        }
        let session = ChatSession()
        let agent = await Agent(
            model: { selection.current ?? first },
            tools: ToolDefinition.builtIn(workingDirectory: workingDirectory),
            environment: SessionEnvironment.probe(workingDirectory: workingDirectory),
            output: session.handle,
            input: session.nextMessage,
        )
        try await Stipple.run(
            ChatView(session: session, agent: agent, selection: selection), options: ChatView.renderOptions)
    }
}
