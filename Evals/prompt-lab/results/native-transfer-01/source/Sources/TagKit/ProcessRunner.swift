import Foundation
import Subprocess
import System

/// Runs a program and collects its output, using swift-subprocess.
enum ProcessRunner {
    struct Result: Equatable {
        var status: Int32
        var output: String
        var errorOutput: String
    }

    enum Failure: Error, Equatable {
        /// The program isn't on `PATH`.
        case notFound
        /// The program printed more than ``ProcessRunner/outputLimit`` bytes.
        case outputTooLarge
    }

    /// The most output collected from one run, so a runaway command can't
    /// fill memory or the model's context.
    static let outputLimit = 1_000_000

    /// Runs `program`, looked up on `PATH`.
    ///
    /// Standard input is empty: the agent reads the user's messages from its
    /// own standard input, and an interactive command must not take them.
    ///
    /// - Parameters:
    ///   - program: The program name.
    ///   - arguments: Its arguments.
    ///   - directory: The working directory of the program.
    ///   - mergingErrors: Sends standard error into `output`, in order, as a
    ///     terminal would show it (`2>&1`).
    /// - Returns: The exit status and everything the program printed. A
    ///   program killed by a signal gets status `128 + signal`, like in a shell.
    /// - Throws: ``Failure`` or a `SubprocessError` if the program can't run.
    static func run(
        _ program: String,
        _ arguments: [String],
        in directory: URL,
        mergingErrors: Bool = false,
    ) async throws -> Result {
        do {
            let workingDirectory = FilePath(directory.path(percentEncoded: false))
            if mergingErrors {
                let result = try await Subprocess.run(
                    .name(program), arguments: .init(arguments), workingDirectory: workingDirectory,
                    output: .string(limit: outputLimit), error: .combinedWithOutput,
                )
                return Result(status: status(result.terminationStatus), output: result.standardOutput, errorOutput: "")
            }
            let result = try await Subprocess.run(
                .name(program), arguments: .init(arguments), workingDirectory: workingDirectory,
                output: .string(limit: outputLimit), error: .string(limit: outputLimit),
            )
            return Result(
                status: status(result.terminationStatus),
                output: result.standardOutput,
                errorOutput: result.standardError,
            )
        } catch let error as SubprocessError where error.code == .executableNotFound {
            throw Failure.notFound
        } catch let error as SubprocessError where error.code == .outputLimitExceeded {
            throw Failure.outputTooLarge
        }
    }

    private static func status(_ status: TerminationStatus) -> Int32 {
        switch status {
        case .exited(let code): code
        case .signaled(let signal): 128 + signal
        }
    }
}
