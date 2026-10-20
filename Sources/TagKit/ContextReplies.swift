import Foundation
import SessionKit

struct ContextReadReply: Encodable {
    var outputID: String
    var source: String
    var sha256: String
    var bytes: Int
    var complete: Bool
    var offset: Int
    var nextOffset: Int?
    var text: String

    enum CodingKeys: String, CodingKey {
        case outputID = "output_id"
        case nextOffset = "next_offset"
        case source, sha256, bytes, complete, offset, text
    }

    static func render(_ page: OutputPage, budget: Int) throws -> String {
        guard budget >= 512 else { throw OutputError.invalidRange }
        var source = ContextText.prefix(page.reference.source, bytes: min(128, budget / 32))
        if source != page.reference.source { source += "…" }
        var reply = Self(
            outputID: page.reference.id,
            source: source,
            sha256: page.reference.sha256, bytes: page.reference.byteCount, complete: page.reference.complete,
            offset: page.offset, nextOffset: page.nextOffset, text: page.text)
        while true {
            let encoded = try ContextText.json(reply)
            if encoded.utf8.count <= budget { return encoded }
            guard !reply.text.isEmpty else { throw OutputError.invalidRange }
            reply.text = ContextText.prefix(reply.text, bytes: reply.text.utf8.count / 2)
            let end = page.offset + reply.text.utf8.count
            reply.nextOffset = end < page.reference.byteCount ? end : nil
        }
    }
}

struct ContextSearchReply: Encodable {
    var queryCount: Int
    var matches: [Match] = []
    var truncated = false
    let coverage = "selected_matches"

    enum CodingKeys: String, CodingKey {
        case queryCount = "query_count"
        case matches, truncated, coverage
    }

    mutating func render(budget: Int) throws -> String {
        guard budget >= 512 else { throw OutputError.invalidRange }
        while true {
            let encoded = try ContextText.json(self)
            if encoded.utf8.count <= budget { return encoded }
            truncated = true
            if matches.count > 1 {
                matches.removeLast()
            } else if let first = matches.first, !first.text.isEmpty {
                matches[0].text = ContextText.prefix(first.text, bytes: first.text.utf8.count / 2)
            } else {
                throw OutputError.invalidRange
            }
        }
    }

    struct Match: Encodable {
        var query: Int
        var outputID: String
        var offset: Int
        var text: String

        init(query: Int, hit: OutputMatch) {
            self.query = query
            outputID = hit.reference.id
            offset = hit.offset
            text = hit.text
        }

        enum CodingKeys: String, CodingKey {
            case outputID = "output_id"
            case query, offset, text
        }
    }
}
