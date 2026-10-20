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
        let codex = CodexProvider(store: credentials)
        let registry = ProviderRegistry(providers: [
            codex,
            OpenCodeGoProvider(credentials: credentials),
            OpenRouterProvider(credentials: credentials),
        ])
        let selection = ModelSelection(registry: registry, credentials: credentials) { provider in
            guard provider == .codex else {
                throw ProviderError.unsupported(provider, detail: "It connects with an API key.")
            }
            try await signIn(codex)
        }
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

    /// Signs in to ChatGPT. When plan usage wasn't granted, asks once more
    /// with the consent screen, where the user can turn it on.
    private static func signIn(_ codex: CodexProvider) async throws {
        do {
            _ = try await codex.signIn()
        } catch ChatGPTSignInError.planUsageNotEnabled {
            _ = try await codex.signIn(forceConsent: true)
        }
    }
}
