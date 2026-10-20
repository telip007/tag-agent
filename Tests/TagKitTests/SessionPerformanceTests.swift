import Foundation
import ModelKit
import SessionKit
import Testing

@testable import Stipple
@testable import TagKit

/// Opt-in release measurements, excluded from normal deterministic correctness checks.
@MainActor
struct SessionPerformanceTests {
    struct Fixture: Decodable {
        var small: UUID
        var large: UUID
    }

    struct Measurement: Encodable {
        var entries: Int
        var visibleRows: Int
        var loadMS: [Double] = []
        var modelHistoryMS: [Double] = []
        var projectionMS: [Double] = []
        var visibleRestoreMS: [Double] = []
        var renderMS: [Double] = []
        var usableInputMS: [Double] = []
        var checksum = 0
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["TAG_SESSION_BENCHMARK_ROOT"] != nil))
    func releaseHydrationMeasurements() async throws {
        #expect(!_isDebugAssertConfiguration())
        let path = try #require(ProcessInfo.processInfo.environment["TAG_SESSION_BENCHMARK_ROOT"])
        let root = URL(filePath: path)
        #expect(
            try String(contentsOf: root.appending(path: ".session-probe-fixture"), encoding: .utf8)
                == "generated fixture")
        let fixture = try JSONDecoder().decode(
            Fixture.self, from: Data(contentsOf: root.appending(path: "benchmark-fixture.json")))
        let store = try await SQLiteSessionStore.open(directory: root.appending(path: "store"))
        try String(ProcessInfo.processInfo.processIdentifier).write(
            to: root.appending(path: "ui.ready"), atomically: true, encoding: .utf8)
        try await waitFor(root.appending(path: "ui.go"))
        var measurements: [Measurement] = []
        for id in [fixture.small, fixture.large] {
            measurements.append(try await measure(store, id: id))
        }
        let copyDirectory = root.appending(path: "startup-store")
        try await store.backup(to: copyDirectory)
        let copy = try await SQLiteSessionStore.open(directory: copyDirectory)
        for (index, id) in [fixture.small, fixture.large].enumerated() {
            measurements[index].usableInputMS = try await startup(copy, id: id, root: root)
        }
        try JSONEncoder().encode(measurements).write(to: root.appending(path: "benchmark-ui.json"), options: .atomic)
        try await waitFor(root.appending(path: "ui.finish"))
    }

    private func waitFor(_ file: URL) async throws {
        let deadline = ContinuousClock.now + .seconds(300)
        while !FileManager.default.fileExists(atPath: file.path) {
            try #require(ContinuousClock.now < deadline)
            try await Task.sleep(for: .milliseconds(2))
        }
    }

    private func measure(_ store: SQLiteSessionStore, id: UUID) async throws -> Measurement {
        var result = Measurement(entries: 0, visibleRows: 0)
        for _ in 0..<32 {
            let loadStart = ContinuousClock.now
            let snapshot = try await store.load(id)
            result.loadMS.append(milliseconds(since: loadStart))
            let modelStart = ContinuousClock.now
            let state = ConversationState(
                active: ScriptedModel([]).active, prompt: { _ in "benchmark" }, snapshot: snapshot)
            result.modelHistoryMS.append(milliseconds(since: modelStart))
            let projectionStart = ContinuousClock.now
            let projection = SessionHydration.project(snapshot)
            result.projectionMS.append(milliseconds(since: projectionStart))
            let visibleStart = ContinuousClock.now
            let session = ChatSession()
            session.restore(projection, pending: [])
            result.visibleRestoreMS.append(milliseconds(since: visibleStart))
            let renderStart = ContinuousClock.now
            let screen = plainText(
                TranscriptPane(
                    session: session, selected: nil, position: .constant(ScrollPosition(edge: .bottom)), loadEarlier: {}
                )
                .frame(width: 116, height: 24), width: 116)
            result.renderMS.append(milliseconds(since: renderStart))
            result.entries = snapshot.entries.count
            result.visibleRows = session.blocks.count
            result.checksum += state.conversation.count + screen.count
        }
        #expect(result.visibleRows == 100)
        #expect(result.checksum > 0)
        return result
    }

    private func startup(_ store: SQLiteSessionStore, id: UUID, root: URL) async throws -> [Double] {
        let config = root.appending(path: "startup-config")
        let credentials = CredentialStore(directory: config, environment: [:])
        let entry = ModelEntry(
            ref: ModelRef(provider: .codex, model: "fixture"), name: "Fixture",
            contextLength: 100_000_000, format: .responses)
        let selection = ModelSelection(
            registry: ProviderRegistry(providers: [FakeProvider(id: .codex, entries: [entry])]),
            settings: SettingsStore(directory: config), credentials: credentials)
        try await selection.select(entry, effort: nil)
        let environment = SessionEnvironment(
            workingDirectory: root, operatingSystem: "test", architecture: "test",
            isMacOS: true, shell: "test", isGitRepository: false)
        var samples: [Double] = []
        for _ in 0..<8 {
            let start = ContinuousClock.now
            let controller = SessionController(
                store: store, selection: selection, environment: environment,
                tools: [], probe: { _ in environment })
            try await controller.open(.resume(id.uuidString))
            controller.draft = SessionDraft()
            let workspace = DurableWorkspace(controller: controller)
            await workspace.settle(timeout: .seconds(30)) {
                controller.session.isWaitingForInput || controller.pauseReason != nil
            }
            try #require(controller.session.isWaitingForInput)
            await workspace.type("ready") { controller.draft.text == "ready" }
            try #require(controller.draft.text == "ready")
            samples.append(milliseconds(since: start))
            try await controller.close()
            workspace.stop()
        }
        return samples
    }

    private func milliseconds(since start: ContinuousClock.Instant) -> Double {
        let elapsed = start.duration(to: .now).components
        return Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15
    }
}
