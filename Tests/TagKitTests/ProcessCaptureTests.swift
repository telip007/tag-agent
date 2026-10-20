import Foundation
import Testing

@testable import TagKit

@MainActor
struct ProcessCaptureTests {
    // Catches collecting/truncating before admission: the last diagnostic must survive >1 MB.
    @Test func largeFailedOutputKeepsTheTailAndExitStatus() async throws {
        let directory = try TemporaryDirectory()
        let outcome = try await ProcessCapture.run(
            "bash", ["-c", "head -c 1100000 /dev/zero | tr '\\0' x; printf 'FINAL_FAILURE' >&2; exit 7"],
            in: directory.url)
        #expect(outcome.content.utf8.count == 1_100_013)
        #expect(outcome.content.hasSuffix("FINAL_FAILURE"))
        #expect(outcome.exitCode == 7)
        #expect(outcome.failed)
        #expect(outcome.complete)
        #expect(!outcome.timedOut)
    }

    // Catches a producer escaping the quota or a partial capture claiming completion.
    @Test func quotaTerminatesAnUnboundedProducerWithExplicitPartialStatus() async throws {
        let directory = try TemporaryDirectory()
        let outcome = try await ProcessCapture.run(
            "bash", ["-c", "while :; do printf '猫\\n'; done"], in: directory.url, byteLimit: 4096)
        #expect(outcome.content.utf8.count <= 4096)
        #expect(outcome.content.hasPrefix("猫\n"))
        #expect(!outcome.content.contains("�"))
        #expect(!outcome.complete)
        #expect(outcome.failed)
    }

    // Catches a timer that waits for descendants to close stdout before returning.
    @Test func timeoutKillsTheCommandGroupAndKeepsAvailableEvidence() async throws {
        let directory = try TemporaryDirectory()
        let marker = directory.url.appending(path: "escaped")
        let ready = directory.url.appending(path: "ready")
        let outcome = try await ProcessCapture.run(
            "bash", ["-c", "(while [ ! -f permit ]; do sleep 0.1; done; touch escaped) & printf before; wait"],
            in: directory.url,
            timeout: .milliseconds(500),
            makeSpool: {
                try CaptureSpool(write: { handle, data in
                    try handle.write(contentsOf: data)
                    if try handle.offset() >= 6 { try Data().write(to: ready) }
                })
            }, waitForDeadline: { try await Self.deadline($0, after: ready) })
        #expect(outcome.content == "before")
        #expect(outcome.timedOut)
        #expect(!outcome.complete)
        #expect(outcome.failed)
        try Data().write(to: directory.url.appending(path: "permit"))
        try await Task.sleep(for: .milliseconds(2100))
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }

    @Test func binaryOutputIsExplicitlyRejectedInsteadOfReplacingEvidence() async throws {
        let directory = try TemporaryDirectory()
        await #expect(throws: ToolError.self) {
            try await ProcessCapture.run("bash", ["-c", "printf '\\377'"], in: directory.url)
        }
    }
}

extension ProcessCaptureTests {
    @Test func timeoutStillAppliesAfterTheChildClosesItsOutput() async throws {
        let directory = try TemporaryDirectory()
        let ready = directory.url.appending(path: "ready")
        let outcome = try await ProcessCapture.run(
            "bash", ["-c", "exec 1>&- 2>&-; touch ready; sleep 30; touch escaped"], in: directory.url,
            timeout: .milliseconds(100), waitForDeadline: { try await Self.deadline($0, after: ready) })
        #expect(outcome.timedOut)
        #expect(!FileManager.default.fileExists(atPath: directory.url.appending(path: "escaped").path))
    }
}

extension ProcessCaptureTests {
    @Test func cancellationKillsDescendantsAndDoesNotBecomeASuccess() async throws {
        let directory = try TemporaryDirectory()
        let marker = directory.url.appending(path: "escaped")
        let task = Task {
            try await ProcessCapture.run(
                "bash", ["-c", "touch started; (sleep 1; touch escaped) & wait"], in: directory.url)
        }
        for _ in 0..<100 {
            if FileManager.default.fileExists(atPath: directory.url.appending(path: "started").path) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(FileManager.default.fileExists(atPath: directory.url.appending(path: "started").path))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        try await Task.sleep(for: .milliseconds(1100))
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }

    @Test func signalsRemainDistinctFromNormalExit() async throws {
        let directory = try TemporaryDirectory()
        let outcome = try await ProcessCapture.run("bash", ["-c", "kill -TERM $$"], in: directory.url)
        #expect(outcome.exitCode == 143)
        #expect(outcome.complete)
        #expect(outcome.failed)
    }
}

extension ProcessCaptureTests {
    @Test func theDeadlineAlsoCoversABlockedStandardInputWriter() async throws {
        let directory = try TemporaryDirectory()
        let ready = directory.url.appending(path: "ready")
        let outcome = try await ProcessCapture.run(
            "bash", ["-c", "touch ready; sleep 30; touch escaped"], in: directory.url,
            input: Data(repeating: 120, count: 1_100_000), timeout: .milliseconds(100),
            waitForDeadline: { try await Self.deadline($0, after: ready) })
        #expect(outcome.timedOut)
        #expect(!outcome.complete)
        #expect(!FileManager.default.fileExists(atPath: directory.url.appending(path: "escaped").path))
    }
}

extension ProcessCaptureTests {
    /// A controlled test clock arms only after the child reaches the exercised state.
    /// Production always sleeps from invocation, including launch and capture overhead.
    @concurrent private static func deadline(_ delay: Duration, after ready: URL) async throws {
        let limit = ContinuousClock.now + .seconds(30)
        while !FileManager.default.fileExists(atPath: ready.path) {
            try Task.checkCancellation()
            guard ContinuousClock.now < limit else { throw ToolError("test child did not reach its ready state") }
            try await Task.sleep(for: .milliseconds(10))
        }
        try await Task.sleep(for: delay)
    }
}
