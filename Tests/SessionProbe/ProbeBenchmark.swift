import Darwin
import Foundation
import ModelKit
import SessionKit

enum ProbeBenchmark {
    struct JSONLLine: Codable {
        var version = 1
        var session: UUID
        var sequence: Int
        var timestamp: Date
        var event: SessionEvent
    }

    struct Target {
        var store: SQLiteSessionStore
        var id: UUID
        var file: FileHandle?
        var url: URL
    }

    struct Result: Encodable {
        var phase: String
        var samplesMS: [Double]
        var encodedBytes: Int
        var logicalCommits: Int
        var entriesBefore: Int64
        var checksum: Int
    }

    @concurrent
    static func run(store: SQLiteSessionStore, id: UUID, boundary: ProbeBoundary, root: URL) async throws {
        let phase = boundary.phase
        let fileURL = root.appending(path: id.uuidString.lowercased() + ".jsonl")
        let file = phase.hasPrefix("jsonl-") ? try FileHandle(forUpdating: fileURL) : nil
        defer { try? file?.close() }
        let summary = try await store.summary(id)
        var sequence = Int(summary.nextSequence)
        if let file, phase != "jsonl-load" { sequence = try lastSequence(file) + 1 }
        let event = payload(large: phase.hasSuffix("1m"))
        let encodedBytes = try SessionCodec.encode(event).count
        try boundary.signal()
        try await wait(boundary.ready.appendingPathExtension("go"))
        let count = phase.hasPrefix("discover-") ? 16 : phase.hasSuffix("1m") || phase.hasSuffix("load") ? 32 : 128
        let target = Target(store: store, id: id, file: file, url: fileURL)
        var samples: [Double] = []
        var checksum = 0
        for index in 0..<count {
            let start = ContinuousClock.now
            checksum += try await operation(
                phase, target: target, event: event, sequence: sequence + index)
            let elapsed = start.duration(to: .now).components
            samples.append(Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15)
        }
        let writes = phase.hasPrefix("sqlite-") || (phase.hasPrefix("jsonl-") && phase != "jsonl-load")
        let result = Result(
            phase: phase, samplesMS: samples, encodedBytes: encodedBytes, logicalCommits: writes ? count : 0,
            entriesBefore: Int64(sequence), checksum: checksum)
        try JSONEncoder().encode(result).write(to: boundary.ready.appendingPathExtension("json"), options: .atomic)
        try await wait(boundary.ready.appendingPathExtension("finish"))
    }

    private static func operation(
        _ phase: String, target: Target, event: SessionEvent, sequence: Int
    ) async throws -> Int {
        let (store, id, file, url) = (target.store, target.id, target.file, target.url)
        switch phase {
        case "sqlite-4k", "sqlite-1m":
            try await store.append(id, event: event)
            return 1
        case "jsonl-4k", "jsonl-1m":
            guard let file else { throw ProbeFailure.usage }
            try writeJSONL(event, sequence: sequence, id: id, file: file)
            try flush(file)
            return 1
        case "list", "discover", "discover-miss", "discover-unicode":
            let query =
                switch phase {
                case "discover": "needle"
                case "discover-miss": "absent-generated-phrase"
                case "discover-unicode": "🌳"
                default: ""
                }
            let rows = try await store.list(workspace: nil, query: query)
            guard rows.count == (phase == "discover-miss" ? 0 : 50) else { throw ProbeFailure.usage }
            return rows.count
        case "search":
            let rows = try await store.search(id, query: "needle")
            guard !rows.isEmpty else { throw ProbeFailure.usage }
            return rows.count
        case "load": return try await store.load(id).entries.count
        case "jsonl-load":
            let records = try Data(contentsOf: url).split(separator: 10).map { data in
                let record = try JSONDecoder().decode(JSONLLine.self, from: Data(data))
                guard record.version == 1 else { throw ProbeFailure.usage }
                return record
            }
            return records.count
        default: throw ProbeFailure.usage
        }
    }

    static func writeJSONL(_ event: SessionEvent, sequence: Int, id: UUID, file: FileHandle) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(JSONLLine(session: id, sequence: sequence, timestamp: Date(), event: event))
        data.append(10)
        try file.write(contentsOf: data)
    }

    static func flush(_ file: FileHandle) throws {
        try file.synchronize()
        guard fcntl(file.fileDescriptor, F_FULLFSYNC) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private static func lastSequence(_ file: FileHandle) throws -> Int {
        let end = try file.seekToEnd()
        try file.seek(toOffset: end > 2_097_152 ? end - 2_097_152 : 0)
        guard let data = try file.readToEnd(), let last = data.split(separator: 10).last else {
            throw ProbeFailure.usage
        }
        let line = try JSONDecoder().decode(JSONLLine.self, from: Data(last))
        try file.seekToEnd()
        return line.sequence
    }

    private static func payload(large: Bool) -> SessionEvent {
        if large {
            return .toolFinished(
                SessionToolResult(
                    call: ToolCall(id: "generated", name: "bash", arguments: "{}"),
                    output: String(repeating: "x", count: 1_048_576), failed: false, durationMilliseconds: 1))
        }
        return .assistant(
            SessionAssistant(message: AssistantMessage(text: String(repeating: "x", count: 4096)), usage: nil))
    }

    private static func wait(_ file: URL) async throws {
        let deadline = ContinuousClock.now + .seconds(300)
        while !FileManager.default.fileExists(atPath: file.path) {
            guard ContinuousClock.now < deadline else { throw ProbeFailure.usage }
            try await Task.sleep(for: .milliseconds(2))
        }
    }
}
