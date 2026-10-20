import Darwin
import Foundation
import SessionKit

/// Internal fixture executable; it never opens a real provider or an unmarked store.
@main
enum SessionProbe {
    static func main() async {
        do { try await run() } catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            exit(1)
        }
    }

    @MainActor
    private static func run() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count == 5, let id = UUID(uuidString: arguments[2]) else { throw ProbeFailure.usage }
        let directory = URL(filePath: arguments[1])
        let root = directory.deletingLastPathComponent()
        guard
            try String(contentsOf: root.appending(path: ".session-probe-fixture"), encoding: .utf8)
                == "generated fixture"
        else {
            throw ProbeFailure.unmarkedFixture
        }
        let store = try await SQLiteSessionStore.open(directory: directory)
        let boundary = ProbeBoundary(phase: arguments[3], ready: URL(filePath: arguments[4]))
        try await dispatch(arguments[0], store: store, id: id, boundary: boundary, root: root)
    }

    @MainActor
    private static func dispatch(
        _ mode: String, store: SQLiteSessionStore, id: UUID, boundary: ProbeBoundary, root: URL
    ) async throws {
        switch mode {
        case "benchmark-seed":
            try await ProbeBenchmarkSeed.run(store: store, root: root)
            try boundary.signal()
        case "benchmark": try await ProbeBenchmark.run(store: store, id: id, boundary: boundary, root: root)
        case "agent": try await ProbeAgent.run(store: store, id: id, boundary: boundary, workspace: root)
        case "lock":
            let owner = try SessionOwnership(directory: store.directory, sessionID: id)
            defer { withExtendedLifetime(owner) {} }
            try await boundary.pause()
        case "prepare-v1":
            try await ProbeJobs.prepareV1(store)
            try boundary.signal()
        case "writer": try await ProbeJobs.write(store: store, id: id, boundary: boundary, root: root)
        case "reader": try await ProbeJobs.read(store: store, boundary: boundary, root: root)
        case "transaction", "hold-input-save":
            try await ProbeJobs.holdTransaction(
                store: store, id: id, boundary: boundary, ownsSession: mode == "transaction")
        case "fault-input", "clear-input-fault":
            try await ProbeJobs.inputFault(store, enabled: mode == "fault-input")
            try boundary.signal()
        case "fault-draft":
            try await ProbeJobs.draftFault(store)
            try boundary.signal()
        case "fault-pointer", "clear-pointer-fault":
            try await ProbeJobs.pointerFault(store, enabled: mode == "fault-pointer")
            try boundary.signal()
        default: throw ProbeFailure.usage
        }
    }
}

enum ProbeFailure: LocalizedError {
    case usage
    case unmarkedFixture

    var errorDescription: String? {
        switch self {
        case .usage: "Usage: SessionProbe <mode> <store> <id> <phase/count> <ready-file> (generated fixtures only)."
        case .unmarkedFixture: "A generated session-probe fixture marker is required."
        }
    }
}
