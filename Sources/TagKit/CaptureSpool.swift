import Foundation

/// Owner-only temporary capture, removed on success, failure and cancellation.
struct CaptureSpool: Sendable {
    let directory: URL
    let handle: FileHandle

    private let writeData: @Sendable (FileHandle, Data) throws -> Void
    private let readData: @Sendable (FileHandle) throws -> Data

    init(
        write: @escaping @Sendable (FileHandle, Data) throws -> Void = { try $0.write(contentsOf: $1) },
        read: @escaping @Sendable (FileHandle) throws -> Data = {
            try $0.seek(toOffset: 0)
            return try $0.readToEnd() ?? Data()
        }
    ) throws {
        writeData = write
        readData = read
        directory = FileManager.default.temporaryDirectory.appending(path: "tag-output-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let file = directory.appending(path: "output")
        guard FileManager.default.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600])
        else {
            try? FileManager.default.removeItem(at: directory)
            throw ToolError("could not create output capture")
        }
        do { handle = try FileHandle(forUpdating: file) } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    func append(_ data: Data) throws {
        do { try writeData(handle, data) } catch { throw ContextStorageFailure(cause: error) }
    }

    func text(complete: Bool) throws -> String {
        let data: Data
        do { data = try readData(handle) } catch { throw ContextStorageFailure(cause: error) }
        // Invalid UTF-8 is an explicit text-format failure, not a spool I/O error.
        return try CaptureText.decode(data, complete: complete)
    }

    func remove() {
        try? handle.close()
        try? FileManager.default.removeItem(at: directory)
    }
}
