import Foundation
import ModelKit
import SessionKit
import TagKit

@MainActor
enum ProbeAgent {
    static func run(store: SQLiteSessionStore, id: UUID, boundary: ProbeBoundary, workspace: URL) async throws {
        let owner = try SessionOwnership(directory: store.directory, sessionID: id)
        defer { withExtendedLifetime(owner) {} }
        let effects = ProbeEffects(file: workspace.appending(path: "effects.txt"), boundary: boundary)
        let tools = [
            ToolDefinition(name: "probe_write", description: "Write a generated fixture effect.", parameters: [:]) {
                _ in
                try await effects.perform()
            }
        ]
        let model = ProbeModel(boundary: boundary, providerIDFile: workspace.appending(path: "provider-id.txt"))
        let entry = ModelEntry(
            ref: ModelRef(provider: .codex, model: "gpt-5.5-codex"), name: "Probe", contextLength: 1_000_000,
            pricing: .free, format: .responses)
        let active = ActiveModel(entry: entry, chatModel: model, effort: nil)
        let environment = SessionEnvironment(
            workingDirectory: workspace, operatingSystem: "fixture", architecture: "fixture",
            isMacOS: true, shell: "fixture", isGitRepository: false)
        var hasInput = true
        let agent = Agent(
            model: { active }, tools: tools, environment: environment,
            now: { Date(timeIntervalSince1970: 1_792_497_600) },
            journal: AgentJournal(
                store: ProbeStore(base: store, boundary: boundary), snapshot: try await store.load(id)),
            output: { _ in },
            input: {
                defer { hasInput = false }
                return hasInput ? .message("run probe") : nil
            })
        try await agent.run()
    }
}

private actor ProbeEffects {
    let file: URL
    let boundary: ProbeBoundary
    private var invocations = 0

    init(file: URL, boundary: ProbeBoundary) {
        self.file = file
        self.boundary = boundary
    }

    func perform() async throws -> String {
        invocations += 1
        try String(invocations).write(to: file, atomically: true, encoding: .utf8)
        if invocations == 1 { try await boundary.pauseIf("effect") }
        return "effect \(invocations)"
    }
}
