import ModelKit
import SessionKit

/// One fixed prefix per explicit compaction epoch; new messages append normally.
enum ContextRequestProjection {
    static func prefix(_ snapshot: SessionSnapshot, system: Message) -> [Message]? {
        guard let projection = snapshot.summary.contextProjection, projection.archiveID != nil else { return nil }
        let visible = projection.visibleSequences(in: snapshot.entries)
        return [system, .user(projection.notice)]
            + snapshot.entries.compactMap { entry in
                visible.contains(entry.sequence) ? message(entry.event) : nil
            }
    }

    static func message(_ event: SessionEvent) -> Message? {
        switch event {
        case .user(let user): .user(user.message)
        case .assistant(let reply): .assistant(reply.message)
        case .toolFinished(let result): .tool(callID: result.call.id, name: result.call.name, content: result.output)
        default: nil
        }
    }
}
