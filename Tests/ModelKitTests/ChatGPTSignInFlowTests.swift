import Foundation
import Synchronization
import Testing

@testable import ModelKit

/// A browser that records the authorization URLs it is sent to and, like a
/// user approving, follows the redirect with the query `answer` gives.
private final class ScriptedBrowser: Sendable {
    private let opened = Mutex<[URL]>([])
    private let answer: @Sendable (_ authorization: [String: String], _ attempt: Int) -> [String: String]?

    init(answer: @escaping @Sendable (_ authorization: [String: String], _ attempt: Int) -> [String: String]?) {
        self.answer = answer
    }

    var urls: [URL] {
        opened.withLock { $0 }
    }

    /// The query of the `index`th authorization URL.
    func query(_ index: Int = 0) -> [String: String] {
        let url = opened.withLock { $0.indices.contains(index) ? $0[index] : nil }
        return url.map { LoopbackRequest(method: "GET", target: "/?" + ($0.query ?? "")).query } ?? [:]
    }

    func open(_ url: URL) {
        let attempt = opened.withLock { opened in
            opened.append(url)
            return opened.count - 1
        }
        let authorization = query(attempt)
        guard let redirect = authorization["redirect_uri"], let answer = answer(authorization, attempt),
            var components = URLComponents(string: redirect)
        else {
            return
        }
        components.queryItems = answer.map { URLQueryItem(name: $0, value: $1) }
        guard let callback = components.url else {
            return
        }
        Task {
            _ = try? await URLSession.shared.data(from: URL(string: redirect + "/../../favicon.ico") ?? callback)
            _ = try? await URLSession.shared.data(from: callback)
        }
    }
}

struct ChatGPTSignInFlowTests {
    private static let approve: @Sendable ([String: String], Int) -> [String: String]? = { authorization, _ in
        ["code": "code-1", "state": authorization["state"] ?? "", "client_id": CodexFixtures.clientID]
    }

    /// A token endpoint that issues tokens for the nonce of the browser's
    /// latest authorization.
    private static func tokenEndpoint(
        _ browser: ScriptedBrowser, scope: String? = nil, failFirst: Bool = false,
    ) -> CodexTestTransport {
        CodexTestTransport { _ in
            let nonce = browser.query(browser.urls.count - 1)["nonce"] ?? ""
            if failFirst, browser.urls.count == 1 {
                return .reply(status: 400, body: #"{"error":"invalid_grant","error_description":"Code used."}"#)
            }
            let idToken = CodexFixtures.idToken(nonce: nonce)
            return .reply(
                status: 200,
                body: scope.map { CodexFixtures.tokenBody(idToken: idToken, scope: $0) }
                    ?? CodexFixtures.tokenBody(idToken: idToken))
        }
    }

    private static func signIn(
        store: CredentialStore, browser: ScriptedBrowser, transport: CodexTestTransport,
        timeout: Duration = .seconds(10),
    ) -> ChatGPTSignIn {
        ChatGPTSignIn(
            store: store, transport: transport, openBrowser: { browser.open($0) }, timeout: timeout, port: 0)
    }

    @Test func registersExchangesTheCodeAndStoresTheAccount() async throws {
        let store = CodexFixtures.store()
        let browser = ScriptedBrowser(answer: Self.approve)
        let transport = Self.tokenEndpoint(browser)
        let account = try await Self.signIn(store: store, browser: browser, transport: transport).signIn()

        let authorization = browser.query()
        #expect(authorization["client_id"] == "dynamic_agent_client")
        #expect(authorization["ext_agent_host_id"] == store.load().chatGPTHostID)
        let exchange = try #require(transport.requests.first)
        #expect(exchange.url?.absoluteString == CodexFixtures.tokenEndpoint)
        #expect(
            CodexFixtures.form(exchange) == [
                "grant_type": "authorization_code", "client_id": CodexFixtures.clientID, "code": "code-1",
                "code_verifier": PKCE(verifier: CodexFixtures.form(exchange)["code_verifier"] ?? "").verifier,
                "redirect_uri": authorization["redirect_uri"] ?? "", "resource": "https://api.openai.com/v1",
            ])
        #expect(
            PKCE(verifier: CodexFixtures.form(exchange)["code_verifier"] ?? "").challenge
                == authorization["code_challenge"])
        #expect(account.clientID == CodexFixtures.clientID)
        #expect(account.refreshToken == "refresh-1")
        #expect(account.email == "user@example.com")
        // The store keeps whole seconds.
        let stored = try #require(store.load().chatGPT)
        #expect(stored.refreshToken == account.refreshToken)
        #expect(abs(stored.expiresAt.timeIntervalSince(account.expiresAt)) < 1)
        #expect(abs(account.expiresAt.timeIntervalSinceNow - 3600) < 60)
        #expect(store.load().chatGPTClientID == CodexFixtures.clientID)
    }

    @Test func startsOverOnceWhenTheCodeIsRejected() async throws {
        let store = CodexFixtures.store()
        let browser = ScriptedBrowser(answer: Self.approve)
        let transport = Self.tokenEndpoint(browser, failFirst: true)
        _ = try await Self.signIn(store: store, browser: browser, transport: transport).signIn()
        #expect(browser.urls.count == 2)
        #expect(browser.query(1)["client_id"] == CodexFixtures.clientID)
        #expect(browser.query(1)["agent_name_hint"] == nil)
    }

    @Test func stopsWhenTheUserDeclines() async {
        let store = CodexFixtures.store()
        let browser = ScriptedBrowser { authorization, _ in
            ["error": "access_denied", "state": authorization["state"] ?? ""]
        }
        await #expect(throws: ChatGPTSignInError.accessDenied) {
            _ = try await Self.signIn(store: store, browser: browser, transport: CodexTestTransport(body: "")).signIn()
        }
        #expect(store.load().chatGPT == nil)
    }

    @Test func keepsTheClientButNotTheAccountWithoutPlanUsage() async {
        let store = CodexFixtures.store()
        let browser = ScriptedBrowser(answer: Self.approve)
        let transport = Self.tokenEndpoint(browser, scope: "openid profile email")
        await #expect(throws: ChatGPTSignInError.planUsageNotEnabled) {
            _ = try await Self.signIn(store: store, browser: browser, transport: transport).signIn()
        }
        #expect(store.load().chatGPT == nil)
        #expect(store.load().chatGPTClientID == CodexFixtures.clientID)
    }

    @Test func givesUpWhenTheBrowserNeverReturns() async {
        let browser = ScriptedBrowser { _, _ in nil }
        let signIn = Self.signIn(
            store: CodexFixtures.store(), browser: browser, transport: CodexTestTransport(body: ""),
            timeout: .milliseconds(100))
        await #expect(throws: ChatGPTSignInError.timedOut) {
            _ = try await signIn.signIn()
        }
    }
}
