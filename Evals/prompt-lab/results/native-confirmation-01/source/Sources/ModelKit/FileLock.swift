import Foundation

/// An exclusive lock shared by every process on the machine, held on a
/// lock file with `flock(2)`. Two Tag sessions use it so they don't write
/// the same file at once, or both spend a rotating refresh token.
///
/// The lock belongs to the open file, so two `FileLock`s on the same path
/// exclude each other in one process too, and the system releases it when a
/// process dies holding it.
struct FileLock: Sendable {
    /// The lock file; created, empty, when first needed.
    let url: URL

    /// How long ``waitingWithLock(_:)`` waits between tries.
    static let pollInterval = Duration.milliseconds(20)

    /// Runs `body` holding the lock, waiting for it without blocking a thread.
    ///
    /// - Throws: What `body` throws, file system errors, or `CancellationError`.
    func waitingWithLock<Result>(_ body: () async throws -> Result) async throws -> Result {
        let handle = try open()
        defer { try? handle.close() }
        while flock(handle.fileDescriptor, LOCK_EX | LOCK_NB) != 0 {
            try await Task.sleep(for: Self.pollInterval)
        }
        defer { flock(handle.fileDescriptor, LOCK_UN) }
        return try await body()
    }

    /// Runs `body` holding the lock, blocking until it is free. For short
    /// critical sections such as a read-modify-write of a small file.
    ///
    /// - Throws: What `body` throws, or file system errors.
    func withLock<Result>(_ body: () throws -> Result) throws -> Result {
        let handle = try open()
        defer { try? handle.close() }
        flock(handle.fileDescriptor, LOCK_EX)
        defer { flock(handle.fileDescriptor, LOCK_UN) }
        return try body()
    }

    private func open() throws -> FileHandle {
        let manager = FileManager.default
        if !manager.fileExists(atPath: url.path) {
            try manager.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            // Never replace a lock file another process just made: the two
            // would lock different files. `.withoutOverwriting` creates it
            // exclusively and fails harmlessly when it exists.
            if (try? Data().write(to: url, options: .withoutOverwriting)) != nil {
                try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            }
        }
        return try FileHandle(forUpdating: url)
    }
}
