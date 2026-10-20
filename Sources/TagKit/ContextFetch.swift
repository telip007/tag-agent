import Foundation
import Synchronization

struct FetchedContext: Sendable {
    let text: String
    let source: String
}

/// No cookies, credentials, HTML rendering, external service or implicit installation.
struct ContextFetch: Sendable {
    let session: URLSession
    init(session: URLSession? = nil) { self.session = session ?? Self.defaultSession }

    static let defaultSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    @concurrent func fetch(
        _ source: String, byteLimit: Int = 32 * 1024 * 1024, timeout: TimeInterval = 30
    ) async throws -> FetchedContext {
        guard (1...32 * 1024 * 1024).contains(byteLimit), timeout > 0, timeout <= 120 else {
            throw ToolError("invalid fetch limit")
        }
        let url = try Self.url(source)
        do {
            return try await withThrowingTaskGroup(of: FetchedContext.self) { group in
                group.addTask { try await load(url, byteLimit: byteLimit, timeout: timeout) }
                group.addTask {
                    try await Task.sleep(for: .seconds(timeout))
                    throw ToolError("fetch timed out; no source was indexed")
                }
                defer { group.cancelAll() }
                guard let result = try await group.next() else { throw CancellationError() }
                try Task.checkCancellation()
                return result
            }
        } catch let error as URLError where error.code == .timedOut {
            try Task.checkCancellation()
            throw ToolError("fetch timed out; no source was indexed")
        }
    }

    private func load(_ url: URL, byteLimit: Int, timeout: TimeInterval) async throws -> FetchedContext {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.setValue("text/*, application/json, application/xml", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request, delegate: ContextRedirectPolicy())
        defer { bytes.task.cancel() }
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw ToolError("fetch failed with HTTP status \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        guard let final = response.url else { throw ToolError("fetch has no final source URL") }
        let source = try Self.url(final.absoluteString).absoluteString
        guard Self.isText(response.mimeType), Self.isUTF8(response.textEncodingName) else {
            throw ToolError("fetch requires UTF-8 text; unsupported content type or encoding")
        }
        guard response.expectedContentLength <= Int64(byteLimit) else { throw ToolError("fetch exceeds byte limit") }
        var content = Data()
        for try await byte in bytes {
            guard content.count < byteLimit else { throw ToolError("fetch exceeds byte limit") }
            content.append(byte)
        }
        try Task.checkCancellation()
        guard let text = String(validating: content, as: UTF8.self) else { throw ToolError("fetch is not valid UTF-8") }
        return FetchedContext(text: text, source: source)
    }

    fileprivate static func url(_ text: String) throws -> URL {
        guard text.utf8.count <= 2048, let url = URL(string: text), let scheme = url.scheme?.lowercased(),
            ["http", "https"].contains(scheme), url.host != nil, url.user == nil, url.password == nil
        else { throw ToolError("use an HTTP(S) URL without embedded credentials, at most 2048 bytes") }
        return url
    }

    private static func isText(_ mime: String?) -> Bool {
        guard let mime = mime?.lowercased() else { return false }
        return mime.hasPrefix("text/") || mime.hasSuffix("+json") || mime.hasSuffix("+xml")
            || ["application/json", "application/xml", "application/javascript", "application/x-ndjson"].contains(mime)
    }

    private static func isUTF8(_ encoding: String?) -> Bool {
        encoding == nil || ["utf-8", "utf8", "us-ascii"].contains(encoding?.lowercased() ?? "")
    }
}

/// Validates redirects before URLSession sends a follow-up request.
private final class ContextRedirectPolicy: NSObject, URLSessionTaskDelegate {
    private let redirects = Mutex<Int>(0)

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        let withinLimit = redirects.withLock { count in
            count += 1
            return count <= 5
        }
        guard withinLimit, let url = request.url, (try? ContextFetch.url(url.absoluteString)) != nil else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
