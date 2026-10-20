public import Foundation

/// Explicit version boundary for the session disk format.
public enum SessionCodec {
    private struct Envelope: Codable {
        var version: Int
        var event: SessionEvent
    }

    private struct Version: Decodable {
        var version: Int
    }

    /// Encodes one semantic event; the work is independent of history length.
    public static func encode(_ event: SessionEvent) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(Envelope(version: 1, event: event))
    }

    /// Rejects unsupported envelopes before interpreting any event payload.
    public static func decode(_ data: Data) throws -> SessionEvent {
        let decoder = JSONDecoder()
        let version = try decoder.decode(Version.self, from: data).version
        guard version == 1 else {
            throw SessionError.unsupportedVersion(version)
        }
        return try decoder.decode(Envelope.self, from: data).event
    }
}
