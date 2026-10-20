import SessionKit

struct ContextHistoryPageReply: Encodable {
    let sequence: Int64
    let bytes: Int
    let offset: Int
    var nextOffset: Int?
    var text: String
    let format = "canonical_event_json"
    let untrusted = true
    enum CodingKeys: String, CodingKey {
        case nextOffset = "next_offset"
        case sequence, bytes, offset, text, format, untrusted
    }

    static func render(_ page: HistoryPage, budget: Int) throws -> String {
        var reply = Self(
            sequence: page.sequence, bytes: page.bytes, offset: page.offset, nextOffset: page.nextOffset,
            text: page.text)
        while true {
            let encoded = try ContextText.json(reply)
            if encoded.utf8.count <= budget { return encoded }
            guard !reply.text.isEmpty else { throw OutputError.invalidRange }
            reply.text = ContextText.prefix(reply.text, bytes: reply.text.utf8.count / 2)
            let end = page.offset + reply.text.utf8.count
            reply.nextOffset = end < page.bytes ? end : nil
        }
    }
}

struct ContextHistorySearchReply: Encodable {
    struct Match: Encodable {
        let sequence: Int64
        let role: String
        var text: String
    }
    var matches: [Match]
    var truncated = false
    let coverage = "selected_history_excerpts"
    let untrusted = true

    static func render(_ references: [SessionReference], budget: Int) throws -> String {
        var reply = Self(
            matches: references.map { Match(sequence: $0.source.sequence, role: $0.source.role, text: $0.text) })
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
