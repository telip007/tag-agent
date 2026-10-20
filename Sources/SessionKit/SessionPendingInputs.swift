public import Foundation
import GRDB

extension SQLiteSessionStore {
    /// Accepts an edited draft and clears its saved UI copy in the same transaction.
    /// Replacement is only allowed for an existing input in this exact session.
    public func acceptDraft(_ id: UUID, input: PendingInput, replacing: Bool) async throws {
        try await database.write { database in
            _ = try Self.summary(id, database: database)
            if replacing {
                try database.execute(
                    sql: "UPDATE pending_inputs SET payload = ? WHERE session_id = ? AND input_id = ?",
                    arguments: [try JSONEncoder().encode(input), Self.key(id), Self.key(input.id)])
                guard database.changesCount == 1 else { throw SessionError.missingInput }
            } else {
                try database.execute(
                    sql: "INSERT INTO pending_inputs(session_id, input_id, payload) VALUES (?, ?, ?)",
                    arguments: [Self.key(id), Self.key(input.id), try JSONEncoder().encode(input)])
            }
            try database.execute(sql: "DELETE FROM session_drafts WHERE session_id = ?", arguments: [Self.key(id)])
        }
    }

    /// Acknowledges input only after it has a durable session-local identity.
    public func accept(_ id: UUID, input: PendingInput) async throws {
        try await database.write { database in
            _ = try Self.summary(id, database: database)
            try database.execute(
                sql: "INSERT INTO pending_inputs(session_id, input_id, payload) VALUES (?, ?, ?)",
                arguments: [Self.key(id), Self.key(input.id), try JSONEncoder().encode(input)])
        }
    }

    /// Atomically appends the exact model input and removes its pending item.
    public func consume(_ id: UUID, inputID: UUID, user: SessionUser) async throws {
        try await database.write { database in
            guard
                let payload = try Data.fetchOne(
                    database,
                    sql: "SELECT payload FROM pending_inputs WHERE session_id = ? AND input_id = ?",
                    arguments: [Self.key(id), Self.key(inputID)])
            else { throw SessionError.missingInput }
            let pending = try JSONDecoder().decode(PendingInput.self, from: payload)
            guard pending.text == user.raw, pending.references == user.references else {
                throw SessionError.invalidEvent
            }
            try database.execute(
                sql: "DELETE FROM pending_inputs WHERE session_id = ? AND input_id = ?",
                arguments: [Self.key(id), Self.key(inputID)])
            guard database.changesCount == 1 else { throw SessionError.missingInput }
            try Self.append(id, event: .user(user), database: database)
        }
    }

    /// Restores accepted items for user review, never automatic dispatch.
    public func pending(_ id: UUID) async throws -> [PendingInput] {
        try await database.read { database in
            _ = try Self.summary(id, database: database)
            let values = try Data.fetchAll(
                database,
                sql: "SELECT payload FROM pending_inputs WHERE session_id = ? ORDER BY position",
                arguments: [Self.key(id)])
            return try values.map { try JSONDecoder().decode(PendingInput.self, from: $0) }
        }
    }
}
