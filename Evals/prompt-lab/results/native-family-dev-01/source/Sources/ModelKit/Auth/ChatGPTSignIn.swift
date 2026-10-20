public import Foundation

/// Why signing in with ChatGPT failed.
public enum ChatGPTSignInError: LocalizedError, Equatable {
    /// Another program holds the redirect's port.
    case callbackPortInUse(Int)
    /// The user declined in the browser.
    case accessDenied
    /// The authorization server answered with an error.
    case authorizationFailed(String)
    /// A first registration's redirect carried no issued client id.
    case registrationIncomplete
    /// The redirect named a client other than the one signing in.
    case clientMismatch
    /// The ID token failed a check.
    case invalidIDToken(String)
    /// The ID token names someone other than the saved account.
    case accountMismatch
    /// The sign-in worked but the user didn't allow use of their ChatGPT
    /// plan. Signing in again with `forceConsent` asks once more.
    case planUsageNotEnabled
    /// The token endpoint refused, with its OAuth error code if any.
    case tokenRequestFailed(status: Int, code: String?, detail: String)
    /// Nothing came back from the browser in time.
    case timedOut

    /// One line saying what went wrong.
    public var errorDescription: String? {
        switch self {
        case .callbackPortInUse(let port):
            "Port \(port) is in use, perhaps by an unfinished sign-in in another app. Finish or cancel it and try again."
        case .accessDenied: "ChatGPT sign-in was cancelled in the browser."
        case .authorizationFailed(let detail): "ChatGPT sign-in failed: \(detail)"
        case .registrationIncomplete: "ChatGPT didn't finish registering Tag Agent. Try signing in again."
        case .clientMismatch: "The browser returned a sign-in for another app registration."
        case .invalidIDToken(let detail): "ChatGPT's ID token was rejected. \(detail)"
        case .accountMismatch: "You signed in to a different ChatGPT account than the saved one."
        case .planUsageNotEnabled:
            "ChatGPT plan usage was not enabled, so Tag Agent can't use your plan. "
                + "Sign in again and allow plan usage, or use an API key with another provider."
        case .tokenRequestFailed(let status, let code, let detail):
            "ChatGPT's token endpoint answered HTTP \(status)\(code.map { " (\($0))" } ?? ""). \(detail)"
        case .timedOut: "ChatGPT sign-in timed out waiting for the browser."
        }
    }

    /// Whether the code or refresh token was rejected for good.
    var isInvalidGrant: Bool {
        if case .tokenRequestFailed(_, "invalid_grant", _) = self {
            return true
        }
        return false
    }
}

/// One authorization attempt: the values sent to the browser and checked
/// when it comes back.
struct ChatGPTAuthorization: Sendable, Equatable {
    /// `dynamic_agent_client` for a first registration, else the issued id.
    var clientID: String
    var hostID: String
    var redirectURI: String
    var state = Base64URL.randomValue()
    var nonce = Base64URL.randomValue()
    var pkce = PKCE.make()
    var idTokenHint: String?
    var loginHint: String?
    /// Asks the user to consent again (`prompt=consent`).
    var forceConsent = false

    /// Whether this registers Tag Agent for the first time.
    var isRegistration: Bool {
        clientID == ChatGPTOAuth.dynamicClientID
    }

    /// The URL to open in the browser.
    var url: URL? {
        var items: [(String, String?)] = [
            ("client_id", clientID),
            ("agent_name_hint", isRegistration ? ChatGPTOAuth.agentName : nil),
            ("ext_agent_host_id", hostID),
            ("id_token_hint", isRegistration ? nil : idTokenHint),
            ("login_hint", isRegistration ? nil : loginHint),
            ("response_type", "code"), ("redirect_uri", redirectURI), ("scope", ChatGPTOAuth.scope),
            ("resource", ChatGPTOAuth.resource), ("state", state), ("nonce", nonce),
            ("code_challenge", pkce.challenge), ("code_challenge_method", "S256"),
        ]
        if forceConsent {
            items.append(("prompt", "consent"))
        }
        guard let base = ChatGPTOAuth.authorizeURL else {
            return nil
        }
        let query = items.compactMap { name, value in value.map { "\(name)=\(ChatGPTTokenClient.formEncode($0))" } }
        return URL(string: base.absoluteString + "?" + query.joined(separator: "&"))
    }

    /// What a redirect to the callback means for this attempt.
    enum Outcome: Equatable {
        /// Not for this attempt (no or another `state`); keep waiting.
        case ignore
        /// The attempt failed.
        case failure(ChatGPTSignInError)
        /// The code to exchange, and the client id to exchange it with.
        case success(code: String, clientID: String)
    }

    /// Checks a redirect's query: `state` first, then an OAuth error, then
    /// the code and client id.
    func outcome(for query: [String: String]) -> Outcome {
        guard query["state"] == state else {
            return .ignore
        }
        if let error = query["error"] {
            return .failure(
                error == "access_denied" ? .accessDenied : .authorizationFailed(query["error_description"] ?? error))
        }
        guard let code = query["code"], !code.isEmpty else {
            return .failure(.authorizationFailed("The redirect carried no code."))
        }
        let returned = query["client_id"].flatMap { $0.isEmpty ? nil : $0 }
        if isRegistration {
            guard let returned, returned != ChatGPTOAuth.dynamicClientID else {
                return .failure(.registrationIncomplete)
            }
            return .success(code: code, clientID: returned)
        }
        if let returned, returned != clientID {
            return .failure(.clientMismatch)
        }
        return .success(code: code, clientID: clientID)
    }
}

/// Signs in with ChatGPT in the system browser so Tag Agent can use the
/// user's plan, and stores the account in the ``CredentialStore``.
///
/// The first sign-in registers Tag Agent as the user's agent; the issued
/// client id is kept, also after signing out, and later sign-ins reuse it.
public struct ChatGPTSignIn: Sendable {
    private let store: CredentialStore
    private let tokens: ChatGPTTokenClient
    private let openBrowser: @Sendable (URL) throws -> Void
    private let now: @Sendable () -> Date
    private let timeout: Duration
    private let port: UInt16

    /// Creates a sign-in.
    ///
    /// - Parameters:
    ///   - store: Where the account and client id are kept.
    ///   - transport: What talks to the token endpoint.
    ///   - openBrowser: Opens the authorization URL; the system browser by default.
    ///   - now: The clock, for token expiry.
    ///   - timeout: How long to wait for the browser.
    ///   - port: The redirect's port. A first registration has to use the
    ///     default, 1455; later sign-ins fall back to any free port when it
    ///     is taken.
    public init(
        store: CredentialStore,
        transport: any HTTPTransport = URLSessionTransport(),
        openBrowser: @escaping @Sendable (URL) throws -> Void = Self.openInSystemBrowser,
        now: @escaping @Sendable () -> Date = { Date() },
        timeout: Duration = .seconds(300),
        port: UInt16 = 1455,
    ) {
        self.store = store
        self.tokens = ChatGPTTokenClient(transport: transport)
        self.openBrowser = openBrowser
        self.now = now
        self.timeout = timeout
        self.port = port
    }

    /// Opens `url` in the default browser with `/usr/bin/open`.
    ///
    /// - Parameter url: The page to open.
    /// - Throws: When `open` can't be started.
    public static func openInSystemBrowser(_ url: URL) throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/open")
        process.arguments = [url.absoluteString]
        try process.run()
    }

    /// Signs in: opens the browser, waits for the redirect, exchanges the
    /// code, checks the ID token and granted scopes, and stores the account.
    /// A rejected code starts over once.
    ///
    /// - Parameter forceConsent: Asks the user to approve plan usage again,
    ///   after ``ChatGPTSignInError/planUsageNotEnabled``.
    /// - Returns: The signed-in account.
    /// - Throws: A ``ChatGPTSignInError``, `CancellationError`, or a
    ///   transport or file system error.
    public func signIn(forceConsent: Bool = false) async throws -> ChatGPTAccount {
        do {
            return try await attempt(forceConsent: forceConsent)
        } catch let error as ChatGPTSignInError where error.isInvalidGrant {
            return try await attempt(forceConsent: forceConsent)
        }
    }

    private func attempt(forceConsent: Bool) async throws -> ChatGPTAccount {
        let credentials = store.load()
        let clientID = credentials.chatGPTClientID ?? ChatGPTOAuth.dynamicClientID
        let saved = credentials.chatGPT.flatMap { $0.clientID == clientID ? $0 : nil }
        let isRegistration = clientID == ChatGPTOAuth.dynamicClientID
        let server = try await startServer(registration: isRegistration)
        defer { server.stop() }
        let authorization = ChatGPTAuthorization(
            clientID: clientID, hostID: try store.chatGPTHostID(),
            redirectURI: "http://127.0.0.1:\(server.port)\(ChatGPTOAuth.callbackPath)",
            idTokenHint: saved?.idToken, loginHint: saved?.email, forceConsent: forceConsent)
        guard let url = authorization.url else {
            throw URLError(.badURL)
        }
        try openBrowser(url)
        let (code, issuedClientID) = try await callback(from: server, for: authorization)
        if isRegistration {
            try store.update { $0.chatGPTClientID = issuedClientID }
        }
        let response = try await tokens.exchange(
            code: code, verifier: authorization.pkce.verifier, clientID: issuedClientID,
            redirectURI: authorization.redirectURI)
        let account = try account(from: response, clientID: issuedClientID, nonce: authorization.nonce, saved: saved)
        try store.update {
            $0.chatGPT = account
            $0.chatGPTClientID = issuedClientID
        }
        return account
    }

    private func startServer(registration: Bool) async throws -> LoopbackServer {
        do {
            return try await LoopbackServer.start(port: port)
        } catch ChatGPTSignInError.callbackPortInUse where !registration {
            return try await LoopbackServer.start(port: 0)
        }
    }

    /// The first redirect for `authorization`, answering every request the
    /// browser makes, within the timeout.
    private func callback(
        from server: LoopbackServer, for authorization: ChatGPTAuthorization,
    ) async throws -> (String, String) {
        let timeout = timeout
        return try await withThrowingTaskGroup(of: (String, String).self) { group in
            group.addTask { try await Self.firstCallback(in: server.requests, for: authorization) }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw ChatGPTSignInError.timedOut
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else {
                throw CancellationError()
            }
            return result
        }
    }

    private static func firstCallback(
        in requests: AsyncStream<LoopbackExchange>, for authorization: ChatGPTAuthorization,
    ) async throws -> (String, String) {
        for await exchange in requests {
            guard exchange.request.path == ChatGPTOAuth.callbackPath else {
                exchange.respond(404, CallbackPage.html("Not found", "This isn't the sign-in callback."))
                continue
            }
            switch authorization.outcome(for: exchange.request.query) {
            case .ignore:
                exchange.respond(400, CallbackPage.html("Sign-in expired", "Start signing in again from Tag Agent."))
            case .failure(let error):
                exchange.respond(400, CallbackPage.html("Not signed in", error.errorDescription ?? ""))
                throw error
            case .success(let code, let clientID):
                exchange.respond(200, CallbackPage.html("Signed in", "You can close this tab and return to Tag Agent."))
                return (code, clientID)
            }
        }
        throw CancellationError()
    }

    /// The account in a token response, after checking the ID token and
    /// that plan usage was granted.
    func account(
        from response: TokenResponse, clientID: String, nonce: String, saved: ChatGPTAccount?,
    ) throws -> ChatGPTAccount {
        guard let idToken = response.idToken else {
            throw ChatGPTSignInError.invalidIDToken("The token response had none.")
        }
        let claims = try IDTokenClaims.validated(idToken, clientID: clientID, nonce: nonce, now: now())
        if let saved, saved.subject != claims.subject {
            throw ChatGPTSignInError.accountMismatch
        }
        let scopes = response.scopes ?? []
        guard scopes.contains(ChatGPTOAuth.planScope) else {
            throw ChatGPTSignInError.planUsageNotEnabled
        }
        guard let refreshToken = response.refreshToken else {
            throw ChatGPTSignInError.tokenRequestFailed(
                status: 200, code: nil, detail: "The token response had no refresh token.")
        }
        return ChatGPTAccount(
            email: claims.email, subject: claims.subject, clientID: clientID, idToken: idToken,
            accessToken: response.accessToken, refreshToken: refreshToken,
            expiresAt: now().addingTimeInterval(response.expiresIn ?? 3600), scopes: scopes)
    }
}

/// The page the browser shows after the redirect.
enum CallbackPage {
    /// A minimal page with a heading and a line of text.
    static func html(_ title: String, _ message: String) -> String {
        let escape: (String) -> String = {
            $0.replacing("&", with: "&amp;").replacing("<", with: "&lt;").replacing(">", with: "&gt;")
        }
        return """
            <!doctype html><html><head><meta charset="utf-8"><title>Tag Agent</title></head>
            <body style="font-family: -apple-system, sans-serif; margin: 4rem auto; max-width: 32rem">
            <h1>\(escape(title))</h1><p>\(escape(message))</p></body></html>
            """
    }
}
