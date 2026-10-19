import Foundation
import Testing

@testable import ModelKit

struct ChatGPTSignInTests {
    // MARK: PKCE

    @Test func derivesTheChallengeAsRFC7636Shows() {
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        #expect(pkce.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func makesFreshURLSafeRandomValues() {
        let first = PKCE.make()
        let second = PKCE.make()
        #expect(first.verifier != second.verifier)
        #expect(first.verifier.count == 43)
        #expect(first.verifier.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        #expect(Base64URL.decode("aGk") == Data("hi".utf8))
    }

    // MARK: Authorization URL

    @Test func registersWithTheDynamicClientFirst() throws {
        let authorization = ChatGPTAuthorization(
            clientID: "dynamic_agent_client", hostID: "urn:uuid:host",
            redirectURI: "http://127.0.0.1:1455/auth/callback", idTokenHint: "old", loginHint: "a@b.c")
        let url = try #require(authorization.url)
        let query = LoopbackRequest(method: "GET", target: "/?" + (url.query ?? "")).query
        #expect(url.absoluteString.hasPrefix("https://auth.openai.com/api/accounts/authorize?"))
        #expect(
            query == [
                "client_id": "dynamic_agent_client", "agent_name_hint": "Tag Agent",
                "ext_agent_host_id": "urn:uuid:host",
                "response_type": "code", "redirect_uri": "http://127.0.0.1:1455/auth/callback",
                "scope": "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct",
                "resource": "https://api.openai.com/v1", "state": authorization.state, "nonce": authorization.nonce,
                "code_challenge": authorization.pkce.challenge, "code_challenge_method": "S256",
            ])
        #expect(url.absoluteString.contains("scope=openid%20profile"))
    }

    @Test func reauthorizesWithTheIssuedClientAndHints() throws {
        let authorization = ChatGPTAuthorization(
            clientID: CodexFixtures.clientID, hostID: "urn:uuid:host",
            redirectURI: "http://127.0.0.1:5/auth/callback",
            idTokenHint: "id-token", loginHint: "user@example.com", forceConsent: true)
        let url = try #require(authorization.url)
        let query = LoopbackRequest(method: "GET", target: "/?" + (url.query ?? "")).query
        #expect(query["client_id"] == CodexFixtures.clientID)
        #expect(query["agent_name_hint"] == nil)
        #expect(query["id_token_hint"] == "id-token")
        #expect(query["prompt"] == "consent")
        #expect(url.absoluteString.contains("login_hint=user%40example.com"))
    }

    // MARK: Callback

    @Test func checksTheStateBeforeAnythingElse() {
        let authorization = ChatGPTAuthorization(clientID: "dynamic_agent_client", hostID: "h", redirectURI: "r")
        #expect(authorization.outcome(for: ["code": "c", "client_id": "oaiapp_1"]) == .ignore)
        #expect(authorization.outcome(for: ["state": "other", "error": "access_denied"]) == .ignore)
        let state = authorization.state
        #expect(authorization.outcome(for: ["state": state, "error": "access_denied"]) == .failure(.accessDenied))
        #expect(
            authorization.outcome(for: ["state": state, "error": "server_error", "error_description": "Down"])
                == .failure(.authorizationFailed("Down")))
        #expect(
            authorization.outcome(for: ["state": state])
                == .failure(.authorizationFailed("The redirect carried no code.")))
    }

    @Test func requiresAnIssuedClientAtRegistration() {
        let authorization = ChatGPTAuthorization(clientID: "dynamic_agent_client", hostID: "h", redirectURI: "r")
        let state = authorization.state
        #expect(authorization.outcome(for: ["state": state, "code": "c"]) == .failure(.registrationIncomplete))
        #expect(
            authorization.outcome(for: ["state": state, "code": "c", "client_id": "dynamic_agent_client"])
                == .failure(.registrationIncomplete))
        #expect(
            authorization.outcome(for: ["state": state, "code": "c", "client_id": "oaiapp_1"])
                == .success(code: "c", clientID: "oaiapp_1"))
    }

    @Test func keepsThePendingClientOnReauthorization() {
        let authorization = ChatGPTAuthorization(clientID: "oaiapp_1", hostID: "h", redirectURI: "r")
        let state = authorization.state
        #expect(authorization.outcome(for: ["state": state, "code": "c"]) == .success(code: "c", clientID: "oaiapp_1"))
        #expect(
            authorization.outcome(for: ["state": state, "code": "c", "client_id": "oaiapp_2"])
                == .failure(.clientMismatch))
    }

    @Test func parsesRequestHeads() {
        let head = Data("GET /auth/callback?code=a%20b&state=s&code=x HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n".utf8)
        let request = LoopbackRequest.parse(head)
        #expect(request?.path == "/auth/callback")
        #expect(request?.query == ["code": "a b", "state": "s"])
        #expect(LoopbackRequest.parse(Data("GET / HTTP/1.1\r\n".utf8)) == nil)
        #expect(LoopbackRequest.parse(Data("hello\r\n\r\n".utf8)) == nil)
    }

    // MARK: ID token

    @Test func validatesTheIDToken() throws {
        let now = Date.now
        let claims = try IDTokenClaims.validated(
            CodexFixtures.idToken(nonce: "n"), clientID: CodexFixtures.clientID, nonce: "n", now: now)
        #expect(claims.subject == "user-1")
        #expect(claims.email == "user@example.com")
        let single = CodexFixtures.jwt([
            "iss": "https://auth.openai.com", "aud": CodexFixtures.clientID, "exp": now.timeIntervalSince1970 + 60,
            "nonce": "n", "sub": "s",
        ])
        let validated = try IDTokenClaims.validated(single, clientID: CodexFixtures.clientID, nonce: "n", now: now)
        #expect(validated.subject == "s")
    }

    @Test func rejectsForeignExpiredOrReplayedIDTokens() {
        let now = Date.now
        func check(_ token: String, clientID: String = CodexFixtures.clientID, nonce: String = "n") {
            #expect(throws: ChatGPTSignInError.self) {
                _ = try IDTokenClaims.validated(token, clientID: clientID, nonce: nonce, now: now)
            }
        }
        let foreign = CodexFixtures.jwt([
            "iss": "https://evil.example", "aud": [CodexFixtures.clientID], "exp": now.timeIntervalSince1970 + 60,
            "sub": "s", "nonce": "n",
        ])
        check(foreign)
        check(CodexFixtures.idToken(nonce: "n"), clientID: "oaiapp_other")
        check(CodexFixtures.idToken(nonce: "n", expires: now - 3600))
        check(CodexFixtures.idToken(nonce: "n"), nonce: "other")
        check("not-a-jwt")
    }

    // MARK: Tokens

    @Test func refusesGrantsWithoutPlanUsage() {
        let signIn = ChatGPTSignIn(store: CodexFixtures.store(), openBrowser: { _ in })
        let response = TokenResponse(
            accessToken: "a", refreshToken: "r", idToken: CodexFixtures.idToken(nonce: "n"), expiresIn: 60,
            scope: "openid email")
        #expect(throws: ChatGPTSignInError.planUsageNotEnabled) {
            _ = try signIn.account(from: response, clientID: CodexFixtures.clientID, nonce: "n", saved: nil)
        }
        let other = CodexFixtures.account(expiresAt: .now)
        var mismatch = response
        mismatch.scope = "chatgpt.tokens.use.direct"
        mismatch.idToken = CodexFixtures.idToken(nonce: "n", subject: "user-2")
        #expect(throws: ChatGPTSignInError.accountMismatch) {
            _ = try signIn.account(from: mismatch, clientID: CodexFixtures.clientID, nonce: "n", saved: other)
        }
    }

    @Test func readsBothShapesOfOAuthErrors() {
        let flatBody = #"{"error":"invalid_grant","error_description":"Gone."}"#
        let flat = ChatGPTTokenClient.oauthError(in: Data(flatBody.utf8))
        #expect(flat.code == "invalid_grant")
        #expect(flat.detail == "Gone.")
        let nestedBody = #"{"error":{"code":"token_expired","message":"Old."}}"#
        let nested = ChatGPTTokenClient.oauthError(in: Data(nestedBody.utf8))
        #expect(nested.code == "token_expired")
        #expect(nested.detail == "Old.")
        #expect(ChatGPTTokenClient.oauthError(in: Data("Bad gateway".utf8)).detail == "Bad gateway")
        #expect(ChatGPTTokenClient.formEncode("a b+c@d") == "a%20b%2Bc%40d")
    }

    @Test func describesEveryError() {
        let errors: [ChatGPTSignInError] = [
            .callbackPortInUse(1455), .accessDenied, .authorizationFailed("x"), .registrationIncomplete,
            .clientMismatch, .invalidIDToken("x"), .accountMismatch, .planUsageNotEnabled,
            .tokenRequestFailed(status: 400, code: "invalid_grant", detail: "x"), .timedOut,
        ]
        for error in errors {
            #expect(error.errorDescription?.isEmpty == false)
        }
        #expect(ChatGPTSignInError.tokenRequestFailed(status: 400, code: "invalid_grant", detail: "").isInvalidGrant)
        #expect(!ChatGPTSignInError.timedOut.isInvalidGrant)
    }
}
