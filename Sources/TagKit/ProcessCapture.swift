import Foundation
import Subprocess
import System

/// Streaming, bounded capture for tools backed by durable context evidence.
/// Isolation here is process lifecycle management, not an OS security sandbox.
enum ProcessCapture {
    private enum End: Sendable {
        case captured(ToolOutcome)
        case timeout
    }

    @concurrent static func run(
        _ program: String, _ arguments: [String], in directory: URL,
        input: Data = Data(), byteLimit: Int = 32 * 1024 * 1024, timeout: Duration = .seconds(120),
        makeSpool: @Sendable () throws -> CaptureSpool = { try CaptureSpool() },
        waitForDeadline: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) async throws -> ToolOutcome {
        guard (1...32 * 1024 * 1024).contains(byteLimit), timeout > .zero else {
            throw ToolError("invalid capture limit")
        }
        let spool = try makeSpool()
        defer { spool.remove() }
        let end = try await withThrowingTaskGroup(of: End.self) { group in
            group.addTask {
                .captured(
                    try await execute(
                        program, arguments, in: directory, spool: spool, byteLimit: byteLimit, input: input))
            }
            group.addTask {
                try await waitForDeadline(timeout)
                return .timeout
            }
            guard let end = try await group.next() else { throw CancellationError() }
            group.cancelAll()
            return end
        }
        try Task.checkCancellation()
        switch end {
        case .captured(var outcome):
            outcome.content = try spool.text(complete: outcome.complete)
            return outcome
        case .timeout:
            return ToolOutcome(
                content: try spool.text(complete: false), failed: true, complete: false, timedOut: true)
        }
    }

    private static func execute(
        _ program: String, _ arguments: [String], in directory: URL, spool: CaptureSpool, byteLimit: Int, input: Data
    ) async throws -> ToolOutcome {
        var options = PlatformOptions()
        options.createSession = true
        options.teardownSequence = teardown
        let result = try await Subprocess.run(
            .name(program), arguments: .init(arguments), workingDirectory: FilePath(directory.path),
            platformOptions: options, input: .data(input), output: .sequence, error: .combinedWithOutput
        ) { execution in
            var count = 0
            for try await buffer in execution.standardOutput {
                let data = Data(buffer: buffer)
                let remaining = byteLimit - count
                try spool.append(Data(data.prefix(remaining)))
                count += min(remaining, data.count)
                if data.count > remaining {
                    await execution.teardown(using: teardown)
                    return false
                }
            }
            return true
        }
        let code = status(result.terminationStatus)
        return ToolOutcome(
            content: "", failed: code != 0 || !result.closureResult,
            complete: result.closureResult, exitCode: code)
    }

    private static let teardown: [TeardownStep] = [
        .send(signal: .kill, toProcessGroup: true, allowedDurationToNextStep: .zero)
    ]

    private static func status(_ status: TerminationStatus) -> Int32 {
        switch status {
        case .exited(let code): code
        case .signaled(let signal): 128 + signal
        }
    }
}
