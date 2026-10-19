import Foundation
import Synchronization

@testable import ModelKit

/// An ``HTTPTransport`` that answers from a script and records requests.
final class CodexTestTransport: HTTPTransport {
    /// A scripted answer: a status and a body, or an error to throw.
    enum Answer: Sendable {
        case reply(status: Int, body: String)
        case failure(URLError)
    }

    private let answer: @Sendable (URLRequest) -> Answer
    private let delay: Duration
    private let recorded = Mutex<[URLRequest]>([])

    init(delay: Duration = .zero, answer: @escaping @Sendable (URLRequest) -> Answer) {
        self.delay = delay
        self.answer = answer
    }

    /// Answers every request with `status` and `body`.
    convenience init(status: Int = 200, body: String) {
        self.init { _ in .reply(status: status, body: body) }
    }

    var requests: [URLRequest] {
        recorded.withLock { $0 }
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (status, body) = try await respond(to: request)
        return (Data(body.utf8), response(request, status))
    }

    func lines(for request: URLRequest) async throws -> (HTTPURLResponse, AsyncThrowingStream<String, any Error>) {
        let (status, body) = try await respond(to: request)
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        return (
            response(request, status),
            AsyncThrowingStream { continuation in
                for line in lines {
                    continuation.yield(line)
                }
                continuation.finish()
            }
        )
    }

    private func respond(to request: URLRequest) async throws -> (Int, String) {
        recorded.withLock { $0.append(request) }
        if delay > .zero {
            try await Task.sleep(for: delay)
        }
        switch answer(request) {
        case .reply(let status, let body): return (status, body)
        case .failure(let error): throw error
        }
    }

    private func response(_ request: URLRequest, _ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: request.url ?? URL(filePath: "/"), statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)
            ?? HTTPURLResponse()
    }
}

/// Values and helpers shared by the Codex tests.
enum CodexFixtures {
    static let clientID = "oaiapp_test"
    static let tokenEndpoint = "https://auth.openai.com/api/accounts/oauth/token"

    /// A credential store in a fresh temporary directory.
    static func store() -> CredentialStore {
        CredentialStore(
            directory: FileManager.default.temporaryDirectory.appending(path: "tag-tests-\(UUID().uuidString)"),
            environment: [:])
    }

    /// An unsigned JWT with `claims` as its payload.
    static func jwt(_ claims: [String: Any]) -> String {
        let header = Base64URL.encode(Data(#"{"alg":"none"}"#.utf8))
        let payload = (try? JSONSerialization.data(withJSONObject: claims)) ?? Data()
        return "\(header).\(Base64URL.encode(payload)).signature"
    }

    /// The claims of a valid ID token for `clientID` and `nonce`.
    static func idToken(nonce: String, subject: String = "user-1", expires: Date = .now + 3600) -> String {
        jwt([
            "iss": "https://auth.openai.com", "aud": [clientID], "exp": expires.timeIntervalSince1970,
            "nonce": nonce, "sub": subject, "email": "user@example.com",
        ])
    }

    /// A token endpoint response.
    static func tokenBody(
        access: String = "access-1", refresh: String? = "refresh-1", idToken: String? = nil,
        scope: String? = "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct",
    ) -> String {
        var json: [String: Any] = ["access_token": access, "expires_in": 3600, "token_type": "Bearer"]
        json["refresh_token"] = refresh
        json["id_token"] = idToken
        json["scope"] = scope
        let data = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
        return String(bytes: data, encoding: .utf8) ?? ""
    }

    /// A stored account expiring at `expiresAt`.
    static func account(expiresAt: Date, refreshToken: String = "refresh-0") -> ChatGPTAccount {
        ChatGPTAccount(
            email: "user@example.com", subject: "user-1", clientID: clientID, idToken: "id-0",
            accessToken: "access-0", refreshToken: refreshToken, expiresAt: expiresAt,
            scopes: ["chatgpt.tokens.use.direct"])
    }

    /// The form fields of a request's body.
    static func form(_ request: URLRequest) -> [String: String] {
        var components = URLComponents()
        components.percentEncodedQuery = request.httpBody.flatMap { String(bytes: $0, encoding: .utf8) }
        var fields: [String: String] = [:]
        for item in components.queryItems ?? [] {
            fields[item.name] = item.value
        }
        return fields
    }

    /// The JSON object of a request's body.
    static func json(_ request: URLRequest) -> [String: Any] {
        guard let body = request.httpBody,
            let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            return [:]
        }
        return object
    }

    /// Server-sent events, one `data:` line per JSON object.
    static func sse(_ events: [String]) -> String {
        events.map { "data: \($0)\n" }.joined(separator: "\n")
    }
}
