import Foundation
import ModelKit
import SessionKit
import Testing

@testable import TagKit

@MainActor
struct ContextFetchTests {
    @Test func fetchAndIndexRetainsExactTextAndFinalRedirectProvenance() async throws {
        let server = try ContextHTTPServer { request in
            if request.hasPrefix("GET /redirect ") {
                return ContextHTTPServer.reply("", status: 302, headers: "Location: /final\r\n")
            }
            return ContextHTTPServer.reply("\u{FEFF}<p>猫\u{0}\nTAIL_WEB_FAILURE</p>", type: "text/html; charset=utf-8")
        }
        let base = try await server.start()
        let fixture = ControllerFixture()
        let store = try await SQLiteSessionStore.open(directory: fixture.directory.appending(path: "sessions"))
        let session = try await store.create(
            workspace: fixture.directory.path,
            context: SessionContext(prompt: "test", model: Models.codex.ref, effort: nil))
        let context = NativeContext(store: store, sessionID: session.id, workingDirectory: fixture.directory)
        let tool = try #require(context.tools.first { $0.name == "fetch_and_index" })
        let args = try #require(
            String(
                data: JSONEncoder().encode(["url": base.appending(path: "redirect").absoluteString]), encoding: .utf8))
        let reply = try await tool.function(args)
        let json = try #require(try JSONSerialization.jsonObject(with: Data(reply.utf8)) as? [String: Any])
        let id = try #require(json["output_id"] as? String)
        let page = try await store.readOutput(session.id, id: id, offset: 0, limit: 200)
        #expect(page.text == "\u{FEFF}<p>猫\u{0}\nTAIL_WEB_FAILURE</p>")
        #expect(page.reference.source == base.appending(path: "final").absoluteString)
        #expect(json["untrusted"] as? Bool == true)
    }

    @Test(arguments: [true, false])
    func oversizeResponsesAreRejectedWithOrWithoutAContentLength(declaringLength: Bool) async throws {
        let server = try ContextHTTPServer { _ in
            ContextHTTPServer.reply(String(repeating: "x", count: 100), declaringLength: declaringLength)
        }
        let url = try await server.start()
        let error = await #expect(throws: ToolError.self) {
            try await ContextFetch().fetch(url.absoluteString, byteLimit: 16)
        }
        #expect(error?.message.contains("limit") == true)
    }

    @Test(arguments: [(404, "text/plain"), (200, "image/png"), (200, "text/plain; charset=iso-8859-1")])
    func unsuccessfulOrUnsupportedSourcesAreNotTreatedAsText(status: Int, mime: String) async throws {
        let server = try ContextHTTPServer { _ in ContextHTTPServer.reply("not indexed", status: status, type: mime) }
        let url = try await server.start()
        await #expect(throws: ToolError.self) { try await ContextFetch().fetch(url.absoluteString) }
    }

    @Test func aStalledFetchHasAWholeRequestDeadline() async throws {
        let server = try ContextHTTPServer { _ in nil }
        let url = try await server.start()
        let observation = try await Self.deadlineObservation(url)
        #expect(observation.error?.message == "fetch timed out; no source was indexed")
        #expect(observation.elapsed < .seconds(2))
        #expect(observation.requestsStopped)
    }

    @Test(arguments: ["file:///tmp/input", "https://user:password@example.com/", "data:text/plain,hello"])
    func urlsCannotSelectLocalFilesOrEmbedCredentials(url: String) async throws {
        await #expect(throws: ToolError.self) { try await ContextFetch().fetch(url) }
    }
}

extension ContextFetchTests {
    @Test func redirectsCannotIntroduceCredentialsAndFetchesDoNotKeepCookies() async throws {
        let server = try ContextHTTPServer { request in
            if request.hasPrefix("GET /credentials ") {
                let host = request.components(separatedBy: "\r\n").first { $0.lowercased().hasPrefix("host: ") }
                let authority = String((host ?? "Host: invalid").dropFirst(6))
                return ContextHTTPServer.reply(
                    "", status: 302, headers: "Location: http://user:password@\(authority)/final\r\n")
            }
            let body = request.lowercased().contains("\r\ncookie:") ? "cookie_seen" : "clean"
            return ContextHTTPServer.reply(body, headers: "Set-Cookie: example=value; Path=/\r\n")
        }
        let url = try await server.start()
        let fetcher = ContextFetch()
        #expect(try await fetcher.fetch(url.absoluteString).text == "clean")
        #expect(try await fetcher.fetch(url.appending(path: "final").absoluteString).text == "clean")
        await #expect(throws: ToolError.self) {
            try await fetcher.fetch(url.appending(path: "credentials").absoluteString)
        }
        #expect(server.requests.count == 3)
    }
    @Test func transportTimeoutUsesTheSamePublicDeadlineError() async throws {
        let server = try ContextHTTPServer { _ in nil }
        let url = try await server.start()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForResource = 0.01
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let error = await #expect(throws: ToolError.self) {
            try await ContextFetch(session: session).fetch(url.absoluteString, timeout: 5)
        }
        #expect(error?.message == "fetch timed out; no source was indexed")
    }
}

extension ContextFetchTests {
    /// Measure before hopping back to the shared main actor used by terminal fixtures.
    @concurrent private static func deadlineObservation(
        _ url: URL
    ) async throws -> FetchDeadlineObservation {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let start = ContinuousClock.now
        var failure: ToolError?
        do { _ = try await ContextFetch(session: session).fetch(url.absoluteString, timeout: 0.1) } catch let error
            as ToolError
        { failure = error }
        let elapsed = ContinuousClock.now - start
        let tasks = await session.allTasks
        let stopped = tasks.allSatisfy { $0.state == .canceling || $0.state == .completed }
        return FetchDeadlineObservation(error: failure, elapsed: elapsed, requestsStopped: stopped)
    }
}

private struct FetchDeadlineObservation: Sendable {
    let error: ToolError?
    let elapsed: Duration
    let requestsStopped: Bool
}
