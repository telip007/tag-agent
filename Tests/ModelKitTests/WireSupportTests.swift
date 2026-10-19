import Foundation
import OpenRouter
import Testing

@testable import ModelKit

struct WireSupportTests {
    @Test func findsTheMessageInErrorBodies() {
        #expect(ProviderError.message(in: #"{"error":{"message":"Nested"}}"#) == "Nested")
        #expect(ProviderError.message(in: #"{"error":"Flat"}"#) == "Flat")
        #expect(ProviderError.message(in: #"{"detail":"Detail"}"#) == "Detail")
        #expect(ProviderError.message(in: #"{"error":{"message":""},"message":"Second"}"#) == "Second")
        #expect(ProviderError.message(in: "  Bad Gateway\n") == "Bad Gateway")
        #expect(ProviderError.message(in: String(repeating: "x", count: 600)).count == 501)
    }

    @Test func mapsStreamedErrorsByCodeAndKind() {
        #expect(
            ProviderError.streamed(["code": 401, "message": "No"], provider: .codex)
                == .signInRequired(.codex, detail: "No"))
        #expect(
            ProviderError.streamed(["code": 400, "message": "Bad"], provider: .codex)
                == .http(.codex, status: 400, detail: "Bad"))
        #expect(ProviderError.streamed("Plain", provider: .codex) == .unavailable(.codex, detail: "Plain"))
        #expect(
            ProviderError.streamed(["code": "rate_limit_exceeded"], provider: .codex)
                == .usageLimit(.codex, detail: #"{"code":"rate_limit_exceeded"}"#, manageURL: nil))
    }

    @Test func describesEveryError() {
        let url = URL(validLiteral: "https://example.com/usage")
        let errors: [ProviderError] = [
            .notConnected(.openCodeGo), .signInRequired(.openCodeGo, detail: "d"),
            .usageLimit(.openCodeGo, detail: "d", manageURL: url),
            .usageLimit(.openCodeGo, detail: "d", manageURL: nil),
            .notEligible(.openCodeGo, detail: "d"), .unsupported(.openCodeGo, detail: "d"),
            .unavailable(.openCodeGo, detail: "d"), .http(.openCodeGo, status: 418, detail: "d"),
            .malformedResponse(.openCodeGo, detail: "d"),
            .unknownModel(ModelRef(provider: .openCodeGo, model: "m")),
        ]
        for error in errors {
            #expect(error.provider == .openCodeGo)
            #expect(error.errorDescription?.isEmpty == false)
        }
        #expect(errors.compactMap(\.recoverySuggestion).count == 7)
        #expect(errors[2].recoverySuggestion?.contains("https://example.com/usage") == true)
    }

    @Test func parsesServerSentEvents() {
        var parser = ServerSentEventParser()
        let lines = [": comment", "event: delta", "data: one", "data: two", "id: 7", "", "", "data:three", "retry"]
        let events = lines.compactMap { parser.feed($0) }
        #expect(events == [ServerSentEvent(event: "delta", data: "one\ntwo")])
        #expect(parser.finish() == ServerSentEvent(data: "three"))
        #expect(parser.finish() == nil)
    }

    @Test func splitsLinesKeepingEmptyOnes() {
        var splitter = LineSplitter()
        let lines = Array("a\r\n\nb".utf8).compactMap { splitter.add($0) }
        #expect(lines == ["a", ""])
        #expect(splitter.finish() == "b")
        #expect(splitter.finish() == nil)
    }

    @Test func readsJSONValues() {
        let value: JSONValue = ["n": 2.0, "f": 1.5, "b": true, "s": "x", "a": [1]]
        #expect(value["n"]?.intValue == 2)
        #expect(value["f"]?.intValue == nil)
        #expect(value["f"]?.doubleValue == 1.5)
        #expect(value["b"]?.boolValue == true)
        #expect(value["s"]?.boolValue == nil)
        #expect(value["s"]?.doubleValue == nil)
        #expect(value["a"]?.arrayValue == [1])
        #expect(value["s"]?["x"] == nil)
        #expect(JSONValue.parse("{") == nil)
        #expect(JSONValue.string("a/b").jsonText == #""a/b""#)
    }
}
