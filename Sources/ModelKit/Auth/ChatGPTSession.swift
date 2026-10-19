public import Foundation

/// Keeps the stored ChatGPT sign-in usable: hands out access tokens,
/// refreshing them shortly before they expire, and signs out.
///
/// Refresh tokens rotate, so refreshes are serialized: concurrent requests
/// share one refresh, and the account is always read back from the
/// ``CredentialStore`` so a refresh by another process is picked up.
public actor ChatGPTSession {
    private let store: CredentialStore
    private let tokens: ChatGPTTokenClient
    private let now: @Sendable () -> Date
    private let refreshMargin: TimeInterval
    private let revocationRetryDelays: [Duration]
    private var refreshing: Task<ChatGPTAccount, any Error>?

    /// Creates a session.
    ///
    /// - Parameters:
    ///   - store: Where the account is kept.
    ///   - transport: What talks to the token and revocation endpoints.
    ///   - now: The clock.
    ///   - refreshMargin: How long before expiry a token is renewed.
    ///   - revocationRetryDelays: The pauses between attempts to revoke on
    ///     sign-out after a network failure or server error.
    public init(
        store: CredentialStore,
        transport: any HTTPTransport = URLSessionTransport(),
        now: @escaping @Sendable () -> Date = { Date() },
        refreshMargin: TimeInterval = 300,
        revocationRetryDelays: [Duration] = [.seconds(1), .seconds(3)],
    ) {
        self.store = store
        self.tokens = ChatGPTTokenClient(transport: transport)
        self.now = now
        self.refreshMargin = refreshMargin
        self.revocationRetryDelays = revocationRetryDelays
    }

    /// The stored account, if signed in.
    public var account: ChatGPTAccount? {
        store.load().chatGPT
    }

    /// A bearer token that is valid for at least the refresh margin,
    /// refreshed first when needed.
    ///
    /// - Returns: The access token.
    /// - Throws: ``ProviderError/notConnected(_:)`` without a sign-in,
    ///   ``ProviderError/signInRequired(_:detail:)`` when the refresh token
    ///   is no longer accepted (the tokens are then cleared), another
    ///   ``ProviderError`` for other refusals, or a transport error (the
    ///   tokens are kept).
    public func accessToken() async throws -> String {
        try await freshAccount().accessToken
    }

    /// Renews the tokens now, even if they haven't expired.
    ///
    /// - Returns: The renewed account.
    /// - Throws: As ``accessToken()``.
    @discardableResult
    public func refresh() async throws -> ChatGPTAccount {
        guard let account = store.load().chatGPT else {
            throw ProviderError.notConnected(.codex)
        }
        return try await sharedRefresh(of: account)
    }

    /// Signs out: revokes the refresh token, then forgets the account. The
    /// issued client id and host id are kept, so the next sign-in reuses
    /// the registration.
    ///
    /// - Returns: Whether the server confirmed the revocation. When it
    ///   didn't, the user can still disconnect Tag Agent in ChatGPT's settings.
    /// - Throws: File system errors from clearing the account.
    @discardableResult
    public func signOut() async throws -> Bool {
        refreshing?.cancel()
        guard let account = store.load().chatGPT else {
            return true
        }
        let revoked = await revoke(account)
        try store.update { credentials in
            credentials.chatGPT = nil
            credentials.chatGPTClientID = credentials.chatGPTClientID ?? account.clientID
        }
        return revoked
    }

    private func freshAccount() async throws -> ChatGPTAccount {
        if let refreshing {
            return try await refreshing.value
        }
        guard let account = store.load().chatGPT else {
            throw ProviderError.notConnected(.codex)
        }
        guard account.expiresAt.timeIntervalSince(now()) <= refreshMargin else {
            return account
        }
        return try await sharedRefresh(of: account)
    }

    private func sharedRefresh(of account: ChatGPTAccount) async throws -> ChatGPTAccount {
        if let refreshing {
            return try await refreshing.value
        }
        let task = Task { try await self.renew(account) }
        refreshing = task
        defer { refreshing = nil }
        return try await task.value
    }

    private func renew(_ account: ChatGPTAccount) async throws -> ChatGPTAccount {
        let response: TokenResponse
        do {
            response = try await tokens.refresh(refreshToken: account.refreshToken, clientID: account.clientID)
        } catch ChatGPTSignInError.tokenRequestFailed(let status, let code, let detail) {
            if let code, ChatGPTOAuth.terminalRefreshErrors.contains(code) {
                try store.update { credentials in
                    if credentials.chatGPT?.subject == account.subject {
                        credentials.chatGPT = nil
                    }
                    credentials.chatGPTClientID = credentials.chatGPTClientID ?? account.clientID
                }
                throw ProviderError.signInRequired(.codex, detail: detail)
            }
            throw status >= 500
                ? ProviderError.unavailable(.codex, detail: detail)
                : ProviderError.http(.codex, status: status, detail: detail)
        }
        var renewed = account
        renewed.accessToken = response.accessToken
        renewed.refreshToken = response.refreshToken ?? account.refreshToken
        renewed.idToken = response.idToken ?? account.idToken
        renewed.scopes = response.scopes ?? account.scopes
        renewed.expiresAt = now().addingTimeInterval(response.expiresIn ?? 3600)
        try store.update { credentials in
            if credentials.chatGPT?.subject == account.subject {
                credentials.chatGPT = renewed
            }
        }
        return renewed
    }

    private func revoke(_ account: ChatGPTAccount) async -> Bool {
        for delay in [Duration.zero] + revocationRetryDelays {
            if delay > .zero {
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    return false
                }
            }
            do {
                let status = try await tokens.revoke(refreshToken: account.refreshToken, clientID: account.clientID)
                if status < 500 {
                    return (200..<300).contains(status)
                }
            } catch {
                continue
            }
        }
        return false
    }
}
