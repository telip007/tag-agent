import Foundation
import SessionKit

/// Bounded user-directed reads, separate from the controller's mutation/ownership API.
protocol SessionReadAccess: Sendable {
    func list(workspace: String?, query: String, after: SessionCursor?, limit: Int) async throws -> [SessionSummary]
    func search(_ id: UUID, query: String) async throws -> [SessionReference]
}

extension SQLiteSessionStore: SessionReadAccess {}
