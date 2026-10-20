import Foundation
import ModelKit
import SessionKit

/// Value projection kept separate from observed live rows and provider messages.
struct SessionProjection {
    var blocks: [TranscriptBlock]
    var history: [String]
    var files: [FileChange]
}

enum SessionHydration {
    static func project(_ snapshot: SessionSnapshot) -> SessionProjection {
        var builder = ProjectionBuilder()
        for entry in snapshot.entries { builder.apply(entry.event) }
        return SessionProjection(
            blocks: builder.contents.enumerated().map { TranscriptBlock(id: $0.offset, content: $0.element) },
            history: builder.history, files: builder.files)
    }
}

private struct ProjectionBuilder {
    var contents: [TranscriptBlock.Content] = []
    var history: [String] = []
    var files: [FileChange] = []
    private var tray: Int?
    private var running: [String: (block: Int, run: Int)] = [:]

    mutating func apply(_ event: SessionEvent) {
        switch event {
        case .user(let user):
            append(.user(user.raw))
            if !user.references.isEmpty { append(.references(user.references)) }
            history.append(user.raw)
        case .assistant(let reply):
            if let text = reply.message.reasoning, !text.isEmpty {
                append(.reasoning(Reasoning(text: text, isStreaming: false)))
            }
            if let text = reply.message.text, !text.isEmpty { append(.reply(text)) }
        case .toolStarted(let call): start(call)
        case .toolFinished(let result): finish(result)
        case .failure(let failure): append(.failure(message: failure.message, recovery: failure.recovery))
        default: break
        }
    }

    private mutating func append(_ content: TranscriptBlock.Content) {
        tray = nil
        contents.append(content)
    }

    private mutating func start(_ call: ToolCall) {
        let run = ToolRun(
            name: call.name, summary: ToolSummary.summarize(call.arguments), state: .unresolved,
            output:
                "No committed result in this snapshot. Effects may be unknown. Recover in the source workspace before deciding what to run."
        )
        if let tray, case .tools(var runs) = contents[tray] {
            running[call.id] = (tray, runs.count)
            runs.append(run)
            contents[tray] = .tools(runs)
        } else {
            tray = contents.count
            running[call.id] = (contents.count, 0)
            contents.append(.tools([run]))
        }
    }

    private mutating func finish(_ result: SessionToolResult) {
        if running[result.call.id] == nil { start(result.call) }
        if let position = running.removeValue(forKey: result.call.id), case .tools(var runs) = contents[position.block]
        {
            runs[position.run].state = result.failed ? .failed : .succeeded
            runs[position.run].output = result.output
            runs[position.run].duration = result.durationMilliseconds.map { .milliseconds($0) }
            contents[position.block] = .tools(runs)
        }
        if result.call.name == "edit_file", !result.failed, let edit = FileEdit.from(arguments: result.call.arguments) {
            append(.edit(edit))
            record(edit)
        }
    }

    private mutating func record(_ edit: FileEdit) {
        if let index = files.firstIndex(where: { $0.path == edit.path }) {
            files[index].added += edit.added
            files[index].removed += edit.removed
        } else {
            files.append(FileChange(path: edit.path, added: edit.added, removed: edit.removed))
        }
    }
}
