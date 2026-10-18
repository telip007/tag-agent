import Testing

@testable import TagKit

struct ToolSummaryTests {
    @Test(arguments: [
        (#"{"command":"swift build","path":"x"}"#, "swift build"),
        (#"{"path":"Sources/Agent.swift"}"#, "Sources/Agent.swift"),
        (#"{"pattern":"TODO","file_type":"swift"}"#, "TODO"),
        (#"{"old_str":"a","new_str":"b"}"#, "b"),
        (#"{"count":3}"#, ""),
        ("{}", ""),
        ("", ""),
        ("not json", "not json"),
        (#"{"command":"echo a\necho b"}"#, "echo a ⏎ echo b"),
    ])
    func picksTheMostTellingArgument(arguments: String, expected: String) {
        #expect(ToolSummary.summarize(arguments) == expected)
    }

    @Test func cutsLongSummaries() {
        let summary = ToolSummary.summarize(#"{"command":"\#(String(repeating: "x", count: 100))"}"#)
        #expect(summary.count == ToolSummary.maxLength)
        #expect(summary.hasSuffix("…"))
    }
}

struct InputHistoryTests {
    let sent = ["one", "two", "three"]

    @Test func walksBackAndRestoresTheDraft() {
        var history = InputHistory()
        #expect(history.older(in: sent, current: "dra") == "three")
        #expect(history.older(in: sent, current: "three") == "two")
        #expect(history.older(in: sent, current: "two") == "one")
        #expect(history.older(in: sent, current: "one") == nil)
        #expect(history.newer(in: sent) == "two")
        #expect(history.newer(in: sent) == "three")
        #expect(history.newer(in: sent) == "dra")
        #expect(history.newer(in: sent) == nil)
        #expect(history.index == nil)
    }

    @Test func nothingToRecallWithoutHistory() {
        var history = InputHistory()
        #expect(history.older(in: [], current: "x") == nil)
        #expect(history.newer(in: []) == nil)
    }

    @Test func resetStartsAFreshLine() {
        var history = InputHistory()
        _ = history.older(in: sent, current: "")
        history.reset()
        #expect(history.index == nil)
        #expect(history.older(in: sent, current: "new") == "three")
    }
}
