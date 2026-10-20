import GRDB

enum OutputMigration {
    static func migrate(_ database: Database) throws {
        try database.execute(
            sql: """
                CREATE TABLE context_outputs (
                    id TEXT PRIMARY KEY NOT NULL,
                    session_id TEXT NOT NULL REFERENCES sessions(id),
                    metadata BLOB NOT NULL,
                    content BLOB NOT NULL,
                    byte_count INTEGER NOT NULL CHECK(byte_count >= 0 AND byte_count = length(content))
                );
                CREATE INDEX context_outputs_session ON context_outputs(session_id);
                PRAGMA user_version = 4;
                """)
    }
}
