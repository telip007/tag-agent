import Foundation

/// Storage is private before SQLite creates any journal or sidecar.
enum SessionFiles {
    static func prepare(_ directory: URL) throws {
        let manager = FileManager.default
        _ = try check(directory, type: .typeDirectory)
        try manager.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        _ = try check(directory, type: .typeDirectory)
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }

    static func create(_ url: URL) throws {
        if try !check(url, type: .typeRegular) {
            do {
                try Data().write(to: url, options: .withoutOverwriting)
            } catch CocoaError.fileWriteFileExists {
                // A concurrent opener created it; preserve the existing inode.
            }
        }
        try protect(url)
    }

    static func protect(_ url: URL) throws {
        guard try check(url, type: .typeRegular) else { throw SessionError.unsafeStoragePath }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func protectIfPresent(_ url: URL) throws {
        if try check(url, type: .typeRegular) { try protect(url) }
    }

    private static func check(_ url: URL, type: FileAttributeType) throws -> Bool {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == type else { throw SessionError.unsafeStoragePath }
            return true
        } catch CocoaError.fileReadNoSuchFile { return false }
    }
}
