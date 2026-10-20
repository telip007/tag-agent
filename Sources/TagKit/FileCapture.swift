import Foundation

extension FileTools {
    /// Reads at most the capture limit plus one byte, refusing nonregular sources.
    @concurrent func captureRead(_ path: String, byteLimit: Int = 32 * 1024 * 1024) async throws -> ToolOutcome {
        guard (1...32 * 1024 * 1024).contains(byteLimit) else { throw ToolError("invalid file capture limit") }
        let file = try url(for: path)
        let values = try file.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true else { throw ToolError("expected a regular text file") }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: byteLimit + 1) ?? Data()
        let complete = data.count <= byteLimit
        return ToolOutcome(
            content: try CaptureText.decode(Data(data.prefix(byteLimit)), complete: complete),
            failed: !complete, complete: complete)
    }
}

enum CaptureText {
    static func decode(_ data: Data, complete: Bool) throws -> String {
        if let text = String(validating: data, as: UTF8.self) { return text }
        if !complete {
            for count in 1...min(3, data.count) {
                let suffix = data.suffix(count)
                if let text = String(validating: data.dropLast(count), as: UTF8.self),
                    isPartialScalar(suffix), suffix.dropFirst().allSatisfy({ $0 & 0xC0 == 0x80 })
                {
                    return text
                }
            }
        }
        throw ToolError("output is not valid UTF-8; text evidence is unavailable")
    }

    private static func isPartialScalar(_ bytes: Data.SubSequence) -> Bool {
        guard let first = bytes.first, (0xC2...0xF4).contains(first) else { return false }
        let width = first < 0xE0 ? 2 : (first < 0xF0 ? 3 : 4)
        guard bytes.count < width else { return false }
        guard let second = bytes.dropFirst().first else { return true }
        switch first {
        case 0xE0: return second >= 0xA0
        case 0xED: return second <= 0x9F
        case 0xF0: return second >= 0x90
        case 0xF4: return second <= 0x8F
        default: return true
        }
    }
}
