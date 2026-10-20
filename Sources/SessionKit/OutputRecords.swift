public import Foundation

/// Immutable identity and provenance for evidence retained outside a prompt.
public struct OutputReference: Sendable, Equatable, Codable {
    /// Opaque identity; never a filesystem path.
    public let id: String
    /// Human-readable source label, treated as untrusted data.
    public let source: String
    /// Originating tool call, when known.
    public let callID: String?
    /// Exact UTF-8 size of the retained bytes.
    public let byteCount: Int
    /// SHA-256 of the retained bytes, including embedded zeroes.
    public let sha256: String
    /// Whether capture reached the end of the original source.
    public let complete: Bool
    /// Time at which these bytes were captured.
    public let createdAt: Date
}

/// A byte-addressed exact excerpt, ending on a Unicode scalar boundary.
public struct OutputPage: Sendable, Equatable {
    /// Evidence to which the range belongs.
    public let reference: OutputReference
    /// Beginning byte offset, zero-based.
    public let offset: Int
    /// Exact retained text; never an LLM summary.
    public let text: String
    /// Next byte offset, or nil at the end of the retained artifact.
    public let nextOffset: Int?
}

/// Capture storage quotas, separate from model-facing admission limits.
public struct OutputLimits: Sendable {
    /// Maximum bytes in a single artifact.
    public let perOutput: Int
    /// Maximum retained bytes across the session's artifacts.
    public let perSession: Int

    /// Creates explicit quotas; invalid values reject writes.
    public init(perOutput: Int = 32 * 1024 * 1024, perSession: Int = 256 * 1024 * 1024) {
        self.perOutput = perOutput
        self.perSession = perSession
    }
}

/// Measured retained evidence; these numbers are not provider token savings.
public struct OutputStatistics: Sendable, Equatable {
    /// Number of immutable artifacts in this session.
    public let outputCount: Int
    /// Total exact UTF-8 bytes retained in their canonical blobs.
    public let storedBytes: Int
}

/// Explicit evidence failures; none silently loses or widens access to data.
public enum OutputError: Error, Sendable, Equatable, LocalizedError {
    /// Artifact is missing or belongs to another session.
    case notFound
    /// Invalid byte range, insufficient room for a scalar, or invalid limit.
    case invalidRange
    /// Entire write rejected because it would exceed the capture quota.
    case quotaExceeded
    /// Persisted bytes or metadata do not satisfy their integrity contract.
    case invalidEvidence
    /// Artifact exceeds the bounded whole-input analysis allowance.
    case analysisInputTooLarge
    /// Empty/oversized query or invalid result-budget parameters.
    case invalidQuery

    /// Useful local feedback without implying that an executed command can be rerun.
    public var errorDescription: String? {
        switch self {
        case .notFound: "No output with that ID exists in this session."
        case .invalidRange: "Use a valid UTF-8 byte offset and a limit between 1 and 16384 bytes."
        case .quotaExceeded: "Output storage quota exceeded. The output was not saved."
        case .invalidEvidence: "Saved output is invalid. The original store was preserved."
        case .analysisInputTooLarge: "Artifact exceeds the bounded analysis input limit. Narrow the source first."
        case .invalidQuery: "Use a nonempty query, 1–20 results and a text budget between 4 and 16384 bytes."
        }
    }
}
