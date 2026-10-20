import Foundation

extension FileTools {
    /// Bounds both traversal accumulation and the final encoded listing.
    @concurrent func captureList(_ path: String, byteLimit: Int = 32 * 1024 * 1024) async throws -> ToolOutcome {
        guard (2...32 * 1024 * 1024).contains(byteLimit) else { throw ToolError("invalid listing capture limit") }
        let root = ProtectedPaths.resolved(try url(for: path))
        guard try root.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            throw ToolError("expected a directory")
        }
        var enumerationFailed = false
        guard
            let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles],
                errorHandler: { _, _ in
                    enumerationFailed = true
                    return false
                })
        else { throw ToolError("could not enumerate directory") }
        var entries: [String] = []
        var components: [String] = []
        var size = 2
        var complete = true
        while let file = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            components = Array(components.prefix(max(0, enumerator.level - 1))) + [file.lastPathComponent]
            do { try protected.check(file) } catch {
                enumerator.skipDescendants()
                continue
            }
            let relative = components.joined(separator: "/")
            let entry =
                try file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true ? relative + "/" : relative
            let added = try ContextText.json(entry).utf8.count + (entries.isEmpty ? 0 : 1)
            guard size + added <= byteLimit else {
                complete = false
                break
            }
            entries.append(entry)
            size += added
        }
        complete = complete && !enumerationFailed
        return ToolOutcome(content: try ContextText.json(entries.sorted()), failed: !complete, complete: complete)
    }
}
