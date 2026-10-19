import Foundation
import Testing

@testable import ModelKit

struct ChatGPTSessionTests {
    private static func store(expiresAt: Date) throws -> CredentialStore {
        let store = CodexFixtures.store()
        _ = try store.chatGPTHostID()
        try store.update {
            $0.chatGPT = CodexFixtures.account(expiresAt: expiresAt)
            $0.chatGPTClientID = CodexFixtures.clientID
        }
        return store
    }

    private static func session(
        _ store: CredentialStore, _ transport: CodexTestTransport, retryDelays: [Duration] = [],
    ) -> ChatGPTSession {
        ChatGPTSession(store: store, transport: transport, revocationRetryDelays: retryDelays)
    }

    @Test func handsOutAFreshTokenWithoutRefreshing() async throws {
        let transport = CodexTestTransport(body: "")
        let session = Self.session(try Self.store(expiresAt: .now + 3600), transport)
        #expect(try await session.accessToken() == "access-0")
        #expect(transport.requests.isEmpty)
    }

    @Test func refreshesNearExpiryAndKeepsTheRotatedTokens() async throws {
        let store = try Self.store(expiresAt: .now + 60)
        let transport = CodexTestTransport(body: CodexFixtures.tokenBody(access: "access-2", refresh: "refresh-2"))
        #expect(try await Self.session(store, transport).accessToken() == "access-2")
        let request = try #require(transport.requests.first)
        #expect(request.url?.absoluteString == CodexFixtures.tokenEndpoint)
        #expect(
            CodexFixtures.form(request) == [
                "grant_type": "refresh_token", "client_id": CodexFixtures.clientID, "refresh_token": "refresh-0",
                "resource": "https://api.openai.com/v1",
            ])
        let stored = try #require(store.load().chatGPT)
        #expect(stored.accessToken == "access-2")
        #expect(stored.refreshToken == "refresh-2")
        #expect(stored.idToken == "id-0")
        #expect(stored.expiresAt > .now + 3000)
    }

    @Test func sharesOneRefreshBetweenConcurrentRequests() async throws {
        let store = try Self.store(expiresAt: .now - 10)
        let transport = CodexTestTransport(delay: .milliseconds(100)) { _ in
            .reply(status: 200, body: CodexFixtures.tokenBody(access: "access-2", refresh: nil))
        }
        let session = Self.session(store, transport)
        async let first = session.accessToken()
        async let second = session.accessToken()
        #expect(try await [first, second] == ["access-2", "access-2"])
        #expect(transport.requests.count == 1)
        #expect(store.load().chatGPT?.refreshToken == "refresh-0")
    }

    @Test func twoProcessesSpendTheRotatingRefreshTokenOnce() async throws {
        // Two sessions on one config directory stand in for two Tag processes.
        let store = try Self.store(expiresAt: .now - 10)
        let other = CredentialStore(directory: store.directory, environment: [:])
        let transport = CodexTestTransport(delay: .milliseconds(100)) { _ in
            .reply(status: 200, body: CodexFixtures.tokenBody(access: "access-2", refresh: "refresh-2"))
        }
        async let first = Self.session(store, transport).accessToken()
        async let second = Self.session(other, transport).accessToken()
        #expect(try await [first, second] == ["access-2", "access-2"])
        #expect(transport.requests.count == 1)
        #expect(store.load().chatGPT?.refreshToken == "refresh-2")
    }

    @Test func clearsTheTokensWhenTheRefreshTokenIsDead() async throws {
        let store = try Self.store(expiresAt: .now)
        let hostID = store.load().chatGPTHostID
        let transport = CodexTestTransport(
            status: 400, body: #"{"error":"refresh_token_reused","error_description":"Reused."}"#)
        await #expect(throws: ProviderError.signInRequired(.codex, detail: "Reused.")) {
            _ = try await Self.session(store, transport).accessToken()
        }
        #expect(store.load().chatGPT == nil)
        #expect(store.load().chatGPTClientID == CodexFixtures.clientID)
        #expect(store.load().chatGPTHostID == hostID)
    }

    @Test func keepsTheTokensWhenTheServerOrNetworkFails() async throws {
        let store = try Self.store(expiresAt: .now)
        await #expect(throws: ProviderError.unavailable(.codex, detail: "Down")) {
            _ = try await Self.session(store, CodexTestTransport(status: 502, body: "Down")).refresh()
        }
        await #expect(throws: ProviderError.http(.codex, status: 400, detail: "Bad client")) {
            let transport = CodexTestTransport(
                status: 400, body: #"{"error":"invalid_client","error_description":"Bad client"}"#)
            _ = try await Self.session(store, transport).refresh()
        }
        await #expect(throws: URLError.self) {
            _ = try await Self.session(store, CodexTestTransport { _ in .failure(URLError(.notConnectedToInternet)) })
                .accessToken()
        }
        #expect(store.load().chatGPT != nil)
    }

    @Test func needsASignIn() async throws {
        let session = Self.session(CodexFixtures.store(), CodexTestTransport(body: ""))
        await #expect(throws: ProviderError.notConnected(.codex)) {
            _ = try await session.accessToken()
        }
        await #expect(throws: ProviderError.notConnected(.codex)) {
            _ = try await session.refresh()
        }
        #expect(await session.account == nil)
        #expect(try await session.signOut())
    }

    @Test func revokesTheRefreshTokenOnSignOut() async throws {
        let store = try Self.store(expiresAt: .now + 3600)
        let transport = CodexTestTransport { request in
            request.httpMethod == "POST"
                ? .reply(status: 200, body: "")
                : .reply(status: 200, body: #"{"revocation_endpoint":"https://auth.openai.com/oauth/revoke"}"#)
        }
        #expect(try await Self.session(store, transport).signOut())
        let revocation = try #require(transport.requests.last)
        #expect(transport.requests.first?.url?.absoluteString.hasSuffix("/.well-known/openid-configuration") == true)
        #expect(revocation.url?.absoluteString == "https://auth.openai.com/oauth/revoke")
        #expect(
            CodexFixtures.form(revocation) == [
                "token": "refresh-0", "token_type_hint": "refresh_token", "client_id": CodexFixtures.clientID,
            ])
        #expect(store.load().chatGPT == nil)
        #expect(store.load().chatGPTClientID == CodexFixtures.clientID)
    }

    @Test func signsOutLocallyWhenRevocationFails() async throws {
        let store = try Self.store(expiresAt: .now + 3600)
        let transport = CodexTestTransport(status: 503, body: "")
        #expect(try await !Self.session(store, transport, retryDelays: [.milliseconds(1)]).signOut())
        #expect(transport.requests.count == 2)
        #expect(store.load().chatGPT == nil)
    }
}
