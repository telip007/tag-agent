public import Foundation
import Synchronization

/// A kernel-held exclusive lock for one active session, released on process death.
public final class SessionOwnership: Sendable {
    private let handle: Mutex<FileHandle?>

    /// Refuses a second owner immediately, including another handle in this process.
    public init(directory: URL, sessionID: UUID) throws {
        try SessionFiles.prepare(directory)
        let locks = directory.appending(path: "locks", directoryHint: .isDirectory)
        try SessionFiles.prepare(locks)
        let url = locks.appending(path: sessionID.uuidString.lowercased() + ".lock")
        try SessionFiles.create(url)
        let handle = try FileHandle(forUpdating: url)
        guard flock(handle.fileDescriptor, LOCK_EX | LOCK_NB) == 0 else {
            try handle.close()
            throw SessionError.sessionInUse
        }
        self.handle = Mutex(handle)
    }

    /// Relinquishes the kernel lock immediately, even if another reference remains.
    /// Repeated calls cannot unlock a subsequent owner of this session.
    public func release() {
        handle.withLock { handle in
            guard let open = handle else { return }
            flock(open.fileDescriptor, LOCK_UN)
            try? open.close()
            handle = nil
        }
    }

    deinit { release() }
}
