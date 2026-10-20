import Foundation

/// The fixed values of Sign in with ChatGPT for open-source apps.
enum ChatGPTOAuth {
    /// Where the browser is sent to sign in.
    static let authorizeURL = URL(string: "https://auth.openai.com/api/accounts/authorize")
    /// Where codes and refresh tokens are exchanged.
    static let tokenURL = URL(string: "https://auth.openai.com/api/accounts/oauth/token")
    /// The OpenID discovery document, which names the revocation endpoint.
    static let discoveryURL = URL(string: "https://auth.openai.com/.well-known/openid-configuration")
    /// Where the user manages the app's share of their plan.
    static let usageURL = URL(string: "https://chatgpt.com/settings/usage")
    /// The ID token's issuer.
    static let issuer = "https://auth.openai.com"
    /// The API the tokens are for.
    static let resource = "https://api.openai.com/v1"
    /// The client id of a first registration; never saved or used for tokens.
    static let dynamicClientID = "dynamic_agent_client"
    /// The name suggested for the agent at first registration.
    static let agentName = "Tag Agent"
    /// The scope that lets the tokens use the ChatGPT plan.
    static let planScope = "chatgpt.tokens.use.direct"
    /// Identity scopes, then plan usage scopes.
    static let scope = "openid profile email offline_access resource.invoke \(planScope)"
    /// The redirect's path; only the port may change between sign-ins.
    static let callbackPath = "/auth/callback"
    /// The port of the first registration's redirect.
    static let registrationPort: UInt16 = 1455
    /// Refresh error codes after which the refresh token is useless.
    static let terminalRefreshErrors: Set<String> = [
        "invalid_grant", "invalid_refresh_token", "token_expired", "refresh_token_expired",
        "refresh_token_invalidated", "refresh_token_reused",
    ]
}

/// What the token endpoint answers to a code exchange or refresh.
struct TokenResponse: Sendable, Decodable, Equatable {
    var accessToken: String
    var refreshToken: String?
    var idToken: String?
    var expiresIn: Double?
    var scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
        case expiresIn = "expires_in"
        case scope
    }

    /// The granted scopes, or `nil` when the response didn't list them.
    var scopes: [String]? {
        scope.map { $0.split(whereSeparator: \.isWhitespace).map(String.init) }
    }
}

/// Talks to the token and revocation endpoints with form-encoded posts.
struct ChatGPTTokenClient: Sendable {
    var transport: any HTTPTransport

    /// Exchanges an authorization code for tokens.
    ///
    /// - Throws: ``ChatGPTSignInError/tokenRequestFailed(status:code:detail:)``
    ///   or a transport error.
    func exchange(code: String, verifier: String, clientID: String, redirectURI: String) async throws -> TokenResponse {
        try await post([
            ("grant_type", "authorization_code"), ("client_id", clientID), ("code", code),
            ("code_verifier", verifier), ("redirect_uri", redirectURI), ("resource", ChatGPTOAuth.resource),
        ])
    }

    /// Renews the tokens. `scope` is left out so the grant stays as it is.
    ///
    /// - Throws: ``ChatGPTSignInError/tokenRequestFailed(status:code:detail:)``
    ///   or a transport error.
    func refresh(refreshToken: String, clientID: String) async throws -> TokenResponse {
        try await post([
            ("grant_type", "refresh_token"), ("client_id", clientID), ("refresh_token", refreshToken),
            ("resource", ChatGPTOAuth.resource),
        ])
    }

    /// Revokes a refresh token at the endpoint the discovery document names.
    ///
    /// - Returns: The HTTP status of the revocation (`200` on success).
    /// - Throws: Transport errors, or a malformed discovery document.
    func revoke(refreshToken: String, clientID: String) async throws -> Int {
        let endpoint = try await revocationEndpoint()
        let request = Self.formRequest(
            endpoint,
            [("token", refreshToken), ("token_type_hint", "refresh_token"), ("client_id", clientID)])
        return try await transport.data(for: request).1.statusCode
    }

    private func revocationEndpoint() async throws -> URL {
        struct Discovery: Decodable {
            var revocationEndpoint: URL
            enum CodingKeys: String, CodingKey { case revocationEndpoint = "revocation_endpoint" }
        }
        guard let url = ChatGPTOAuth.discoveryURL else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await transport.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(Discovery.self, from: data).revocationEndpoint
    }

    private func post(_ fields: [(String, String)]) async throws -> TokenResponse {
        guard let url = ChatGPTOAuth.tokenURL else {
            throw URLError(.badURL)
        }
        let (data, response) = try await transport.data(for: Self.formRequest(url, fields))
        guard (200..<300).contains(response.statusCode) else {
            let (code, detail) = Self.oauthError(in: data)
            throw ChatGPTSignInError.tokenRequestFailed(status: response.statusCode, code: code, detail: detail)
        }
        do {
            return try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            throw ChatGPTSignInError.tokenRequestFailed(
                status: response.statusCode, code: nil, detail: "The token response couldn't be read.")
        }
    }

    /// A form-encoded `POST` of `fields` to `url`.
    static func formRequest(_ url: URL, _ fields: [(String, String)]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(TagUserAgent.value, forHTTPHeaderField: "User-Agent")
        request.httpBody = Data(fields.map { "\(formEncode($0))=\(formEncode($1))" }.joined(separator: "&").utf8)
        return request
    }

    /// Percent-encodes everything but the characters form encoding leaves alone.
    static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    /// The error code and message of an OAuth error body: either
    /// `{"error":"code","error_description":"…"}` or
    /// `{"error":{"code":"…","message":"…"}}`.
    static func oauthError(in data: Data) -> (code: String?, detail: String) {
        struct Nested: Decodable {
            var code: String?
            var message: String?
        }
        struct Body: Decodable {
            var error: String?
            var errorDescription: String?
            var nested: Nested?
            enum CodingKeys: String, CodingKey {
                case error
                case errorDescription = "error_description"
            }
            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                error = try? container.decodeIfPresent(String.self, forKey: .error)
                nested = try? container.decodeIfPresent(Nested.self, forKey: .error)
                errorDescription = try? container.decodeIfPresent(String.self, forKey: .errorDescription)
            }
        }
        let text = (String(bytes: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let body = try? JSONDecoder().decode(Body.self, from: data) else {
            return (nil, text)
        }
        let code = body.error ?? body.nested?.code
        return (code, body.errorDescription ?? body.nested?.message ?? code ?? text)
    }
}

/// The claims of an ID token that sign-in checks.
struct IDTokenClaims: Sendable, Equatable {
    var issuer: String
    var audience: [String]
    var expiresAt: Date
    var nonce: String?
    var subject: String
    var email: String?

    /// Decodes `token`'s payload and checks it was issued by OpenAI for
    /// `clientID`, in answer to `nonce`, and hasn't expired.
    ///
    /// The signature isn't verified against OpenAI's keys: the token comes
    /// straight from the token endpoint over TLS, which OpenID Connect Core
    /// §3.1.3.7 allows in place of checking the signature.
    ///
    /// - Throws: ``ChatGPTSignInError/invalidIDToken(_:)``.
    static func validated(_ token: String, clientID: String, nonce: String, now: Date) throws -> Self {
        let claims = try decode(token)
        guard claims.issuer == ChatGPTOAuth.issuer else {
            throw ChatGPTSignInError.invalidIDToken("It was issued by \(claims.issuer).")
        }
        guard claims.audience.contains(clientID) else {
            throw ChatGPTSignInError.invalidIDToken("It was issued for another client.")
        }
        guard claims.expiresAt > now.addingTimeInterval(-60) else {
            throw ChatGPTSignInError.invalidIDToken("It has expired.")
        }
        guard claims.nonce == nonce else {
            throw ChatGPTSignInError.invalidIDToken("Its nonce doesn't match this sign-in.")
        }
        return claims
    }

    /// The claims in a JWT's payload, unchecked.
    ///
    /// - Throws: ``ChatGPTSignInError/invalidIDToken(_:)`` when it isn't a JWT.
    static func decode(_ token: String) throws -> Self {
        struct Payload: Decodable {
            var iss: String
            var aud: Audience
            var exp: Double
            var nonce: String?
            var sub: String
            var email: String?
        }
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, let data = Base64URL.decode(parts[1]),
            let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else {
            throw ChatGPTSignInError.invalidIDToken("It isn't a readable JWT.")
        }
        return Self(
            issuer: payload.iss, audience: payload.aud.values, expiresAt: Date(timeIntervalSince1970: payload.exp),
            nonce: payload.nonce, subject: payload.sub, email: payload.email)
    }
}

/// A JWT `aud` claim: one string or several.
private struct Audience: Decodable {
    var values: [String]

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            values = [value]
        } else {
            values = try container.decode([String].self)
        }
    }
}
