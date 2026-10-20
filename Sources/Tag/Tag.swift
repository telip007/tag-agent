import ArgumentParser
import Foundation
import ModelKit
import SessionKit
import Stipple
import TagKit

@main
struct Tag: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "A coding agent with durable local sessions.")

    @Flag(name: .customLong("new"), help: "Start a new session (the default), keeping previous conversations.")
    var newSession = false

    @Option(help: "Continue a saved session by full ID or unique prefix.")
    var resume: String?

    func validate() throws {
        if newSession && resume != nil { throw ValidationError("Use either --new or --resume <id>.") }
    }

    var startup: SessionController.Startup {
        resume.map(SessionController.Startup.resume) ?? .new
    }

    mutating func run() async throws {
        try await Self.chat(startup: startup)
    }

    /// Runs the chat UI until the user quits or the agent fails.
    @MainActor
    private static func chat(startup: SessionController.Startup) async throws {
        let workingDirectory = URL(filePath: FileManager.default.currentDirectoryPath, directoryHint: .isDirectory)
            .standardizedFileURL.resolvingSymlinksInPath()
        let store = try await SQLiteSessionStore.open(directory: ConfigDirectory.url().appending(path: "sessions"))
        let existing: SessionSummary?
        switch startup {
        case .new: existing = nil
        case .continueLast: existing = try await store.lastSession(workspace: workingDirectory.path)
        case .resume(let prefix): existing = try await store.resolve(prefix)
        }
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
        let restored = await selection.restoreLastModel()
        if !restored, existing == nil {
            try await Stipple.run(OnboardingView(selection: selection), options: OnboardingView.renderOptions)
        }
        if existing == nil, selection.current == nil { return }
        let controller = await SessionController(
            store: store, selection: selection,
            environment: SessionEnvironment.probe(workingDirectory: workingDirectory),
            tools: ToolDefinition.builtIn(workingDirectory: workingDirectory))
        try await controller.open(startup)
        try await Stipple.run(ChatView(controller: controller), options: ChatView.renderOptions)
        try await controller.close()
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
