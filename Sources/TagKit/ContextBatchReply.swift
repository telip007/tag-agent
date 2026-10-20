import SessionKit

struct ContextBatchReply: Encodable {
    let outputID: String
    let bytes: Int
    let commands: Int
    let executed: Int
    let failed: Bool
    let complete: Bool
    let coverage = "batch_selected_matches"
    let readTool = "read_output"
    var matches: [ContextSearchReply.Match]
    var truncated = false

    enum CodingKeys: String, CodingKey {
        case outputID = "output_id"
        case readTool = "read_tool"
        case bytes, commands, executed, failed, complete, coverage, matches, truncated
    }

    static func render(
        manifest: OutputReference, entries: [ContextBatchEntry], matches: [ContextSearchReply.Match], budget: Int
    ) throws -> String {
        var reply = Self(
            outputID: manifest.id, bytes: manifest.byteCount, commands: entries.count,
            executed: entries.filter { $0.status != "not_started" }.count,
            failed: entries.contains(where: \.failed), complete: entries.allSatisfy(\.complete), matches: matches)
        while true {
            let encoded = try ContextText.json(reply)
            if encoded.utf8.count <= budget { return encoded }
            reply.truncated = true
            if reply.matches.count > 1 {
                reply.matches.removeLast()
            } else if let first = reply.matches.first, !first.text.isEmpty {
                reply.matches[0].text = ContextText.prefix(first.text, bytes: first.text.utf8.count / 2)
            } else {
                throw OutputError.invalidRange
            }
        }
    }
}
