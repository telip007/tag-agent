import Foundation

struct ProbeBoundary: Sendable {
    let phase: String
    let ready: URL

    func pauseIf(_ phase: String) async throws {
        if self.phase == phase { try await pause() }
    }

    func pause() async throws {
        try signal()
        while true { try await Task.sleep(for: .seconds(30)) }
    }

    func signal() throws {
        try String(ProcessInfo.processInfo.processIdentifier).write(to: ready, atomically: true, encoding: .utf8)
    }

    func waitForStart(in root: URL) async throws {
        let path = root.appending(path: "go").path
        while !FileManager.default.fileExists(atPath: path) { try await Task.sleep(for: .milliseconds(5)) }
    }
}
