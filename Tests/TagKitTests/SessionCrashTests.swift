import Darwin
import Foundation
import ModelKit
import SessionKit
import Testing

@testable import TagKit

@MainActor
struct SessionCrashTests {
    @Test func aContendedDraftWriteFailsWithoutReplacingTheCommittedDraft() async throws {
        let fixture = ControllerFixture()
        let store = try await SQLiteSessionStore.open(directory: fixture.directory.appending(path: "sessions"))
        let session = try await store.create(workspace: fixture.directory.path, context: context)
        try await store.saveDraft(session.id, draft: SessionDraft(text: "committed draft"))
        let child = try await ChildSessionProbe.start(
            mode: "hold-input-save", store: store, id: session.id, phase: "0")
        var finished = false
        var failed = false
        let writer = Task {
            do { try await store.saveDraft(session.id, draft: SessionDraft(text: "blocked replacement")) } catch {
                failed = true
            }
            finished = true
        }
        let deadline = ContinuousClock.now + .seconds(8)
        while !finished, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        #expect(finished && failed, "The blocked write must fail before the lock holder is released.")
        #expect(try await child.killAndWait().status == 137)
        await writer.value
        #expect(failed)
        #expect(try await store.draft(session.id).text == "committed draft")
    }

    @Test func anUncommittedTransactionRollsBackAndItsJournalIsPrivate() async throws {
        let fixture = ControllerFixture()
        let store = try await SQLiteSessionStore.open(directory: fixture.directory.appending(path: "sessions"))
        let session = try await store.create(workspace: fixture.directory.path, context: context)
        let child = try await ChildSessionProbe.start(mode: "transaction", store: store, id: session.id, phase: "0")
        let journal = store.directory.appending(path: "sessions.sqlite-journal")
        #expect(try FileManager.default.attributesOfItem(atPath: journal.path)[.posixPermissions] as? Int == 0o600)
        #expect(try await child.killAndWait().status == 137)
        let reopened = try await SQLiteSessionStore.open(directory: store.directory)
        #expect(try await reopened.summary(session.id) == session)
        #expect(try await reopened.list(workspace: nil, query: "uncommitted").isEmpty)
    }

    @Test func concurrentWritersAndReaderShareOneMigratedStore() async throws {
        let fixture = ControllerFixture()
        let store = try await SQLiteSessionStore.open(directory: fixture.directory.appending(path: "sessions"))
        let first = try await store.create(workspace: fixture.directory.path, context: context)
        let second = try await store.create(workspace: fixture.directory.path, context: context)
        let prepared = try await ChildSessionProbe.start(mode: "prepare-v1", store: store, id: first.id, phase: "0")
        #expect(try await prepared.wait().status == 0)
        let children = try await withThrowingTaskGroup(of: ChildSessionProbe.self) { group in
            for (mode, id, count) in [
                ("writer", first.id, "40"), ("writer", second.id, "40"), ("reader", first.id, "400"),
            ] {
                group.addTask { try await ChildSessionProbe.start(mode: mode, store: store, id: id, phase: count) }
            }
            var children: [ChildSessionProbe] = []
            for try await child in group { children.append(child) }
            return children
        }
        try #require(children.count == 3)
        try Data().write(to: fixture.directory.appending(path: "go"), options: .atomic)
        for child in children {
            let result = try await child.wait()
            if result.status != 0 { Issue.record("Child failed: \(result.errorOutput.prefix(500))") }
        }
        #expect(try await store.entries(first.id).map(\.sequence) == Array(0...40).map(Int64.init))
        #expect(try await store.entries(second.id).map(\.sequence) == Array(0...40).map(Int64.init))
        #expect(try await store.summary(first.id).nextSequence == 41)
        #expect(try await store.summary(second.id).nextSequence == 41)
        let backups = try FileManager.default.contentsOfDirectory(
            atPath: store.directory.appending(path: "backups").path)
        #expect(backups.count == 1)
        #expect(try await store.diagnostics().journalMode == "delete")
    }

    @Test func kernelOwnershipIsReleasedByProcessDeath() async throws {
        let fixture = ControllerFixture()
        let store = try await SQLiteSessionStore.open(directory: fixture.directory.appending(path: "sessions"))
        let session = try await store.create(workspace: fixture.directory.path, context: context)
        let child = try await ChildSessionProbe.start(mode: "lock", store: store, id: session.id, phase: "lock")
        #expect(throws: SessionError.sessionInUse) {
            try SessionOwnership(directory: store.directory, sessionID: session.id)
        }
        #expect(try await child.killAndWait().status == 137)
        let owner = try SessionOwnership(directory: store.directory, sessionID: session.id)
        withExtendedLifetime(owner) {}
    }

    @Test func killedAgentBoundariesRecoverWithoutRepeatingEffectsOrLosingAcceptedInputs() async throws {
        for phase in [
            "before-accept", "accept", "input", "request", "stream", "reply", "start", "effect", "result", "second",
            "final",
        ] {
            try await verifyKilledBoundary(phase)
        }
    }

    private var context: SessionContext { SessionContext(prompt: "initial", model: Models.codex.ref, effort: nil) }

    private func verifyKilledBoundary(_ phase: String) async throws {
        let fixture = ControllerFixture()
        let store = try await SQLiteSessionStore.open(directory: fixture.directory.appending(path: "sessions"))
        let session = try await store.create(workspace: fixture.directory.path, context: context)
        let child = try await ChildSessionProbe.start(mode: "agent", store: store, id: session.id, phase: phase)
        #expect(try await child.killAndWait().status == 137)
        let owner = try SessionOwnership(directory: store.directory, sessionID: session.id)
        let before = try await store.summary(session.id)
        let hasReply = ["reply", "start", "effect", "result", "second", "follow-up", "final"].contains(phase)
        #expect(before.cost == (phase == "final" ? 0.375 : hasReply ? 0.125 : 0))
        let effectFile = fixture.directory.appending(path: "effects.txt")
        let effects = try? Data(contentsOf: effectFile)
        let recovered = try await store.recover(session.id)
        #expect(recovered.summary.providerSessionID == session.providerSessionID)
        #expect(recovered.summary.cost == before.cost)
        #expect(recovered.summary.latestUsage == before.latestUsage)
        #expect(try await store.pending(session.id).count == (phase == "accept" ? 1 : 0))
        #expect((try? Data(contentsOf: effectFile)) == effects)
        #expect(try await store.recover(session.id).entries == recovered.entries)
        verifyResults(recovered.entries, phase: phase)
        if ["stream", "reply", "start", "effect", "result", "second", "follow-up", "final"].contains(phase) {
            let providerID = try String(
                contentsOf: fixture.directory.appending(path: "provider-id.txt"), encoding: .utf8)
            #expect(providerID == session.providerSessionID)
        }
        withExtendedLifetime(owner) {}
    }

    private func verifyResults(_ entries: [SessionEntry], phase: String) {
        let results = entries.compactMap { entry -> SessionToolResult? in
            if case .toolFinished(let result) = entry.event { return result }
            return nil
        }
        if ["reply", "start", "effect", "result", "second", "follow-up", "final"].contains(phase) {
            #expect(results.map(\.call.id) == ["first", "second"])
            #expect(results.first?.failed == !["result", "second", "follow-up", "final"].contains(phase))
            if ["start", "effect"].contains(phase) { #expect(results.first?.output.contains("unknown") == true) }
            if phase == "reply" { #expect(results.allSatisfy { $0.output.contains("not executed") }) }
            if phase == "second" { #expect(results.last?.output.contains("unknown") == true) }
            if ["result", "second", "follow-up", "final"].contains(phase) {
                #expect(results.first?.output == "effect 1")
            }
            if phase == "final" {
                #expect(results.allSatisfy { !$0.failed })
                #expect(entries.allSatisfy { if case .failure = $0.event { false } else { true } })
            }
        } else {
            #expect(results.isEmpty)
        }
        if phase == "stream" {
            #expect(entries.allSatisfy { if case .assistant = $0.event { false } else { true } })
        }
    }
}

@MainActor
final class ChildSessionProbe {
    private let task: Task<Result<ProcessRunner.Result, any Error>, Never>
    private let pid: Int32

    private init(task: Task<Result<ProcessRunner.Result, any Error>, Never>, pid: Int32) {
        self.task = task
        self.pid = pid
    }

    deinit { task.cancel() }

    static func start(
        mode: String, store: SQLiteSessionStore, id: UUID, phase: String
    ) async throws -> ChildSessionProbe {
        let executable = try await SessionProbeExecutable.shared.url()
        let root = store.directory.deletingLastPathComponent()
        try Data("generated fixture".utf8).write(to: root.appending(path: ".session-probe-fixture"), options: .atomic)
        let ready = root.appending(path: "\(UUID().uuidString).ready")
        let arguments = [
            "LLVM_PROFILE_FILE=" + root.appending(path: "child-%p-%m.profraw").path, executable.path,
            mode, store.directory.path, id.uuidString, phase, ready.path,
        ]
        let task = Task { () -> Result<ProcessRunner.Result, any Error> in
            do { return .success(try await ProcessRunner.run("env", arguments, in: root)) } catch {
                return .failure(error)
            }
        }
        for _ in 0..<400 {
            if let text = try? String(contentsOf: ready, encoding: .utf8),
                let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines))
            {
                return ChildSessionProbe(task: task, pid: pid)
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        task.cancel()
        let result = await task.value
        throw ProbeTestFailure.notReady(String(describing: result))
    }

    func killAndWait() async throws -> ProcessRunner.Result {
        guard Darwin.kill(pid, SIGKILL) == 0 else {
            task.cancel()
            _ = await task.value
            throw ProbeTestFailure.signalFailed
        }
        return try await task.value.get()
    }

    func wait() async throws -> ProcessRunner.Result { try await task.value.get() }
}

private actor SessionProbeExecutable {
    static let shared = SessionProbeExecutable()
    private var prepared: URL?
    private var isPreparing = false

    func url() async throws -> URL {
        while isPreparing { try await Task.sleep(for: .milliseconds(5)) }
        if let prepared { return prepared }
        isPreparing = true
        defer { isPreparing = false }
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let candidates = [".build/debug/SessionProbe", ".build/out/Products/Debug/SessionProbe"].map {
            root.appending(path: $0)
        }
        guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
            throw ProbeTestFailure.executableNotBuilt
        }
        let verified = try await ProcessRunner.run("codesign", ["--verify", executable.path], in: root)
        if verified.status != 0 {
            let signed = try await ProcessRunner.run(
                "codesign", ["--force", "--sign", "-", executable.path], in: root)
            guard signed.status == 0 else { throw ProbeTestFailure.notReady(signed.errorOutput) }
        }
        prepared = executable
        return executable
    }
}

private enum ProbeTestFailure: LocalizedError {
    case executableNotBuilt
    case signalFailed
    case notReady(String)

    var errorDescription: String? {
        switch self {
        case .executableNotBuilt: "SessionProbe was not built."
        case .signalFailed: "Could not stop the test-owned child."
        case .notReady(let detail): "SessionProbe did not become ready: \(detail.prefix(500))"
        }
    }
}
