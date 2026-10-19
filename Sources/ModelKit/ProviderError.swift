public import Foundation

/// What can go wrong talking to a provider, with what the user can do about it.
public enum ProviderError: LocalizedError, Equatable {
    /// No credentials are stored for the provider.
    case notConnected(ProviderID)
    /// The sign-in expired or was revoked; the user has to sign in again.
    case signInRequired(ProviderID, detail: String)
    /// The user's plan or the app's share of it is used up. `manageURL` is
    /// where the user manages usage.
    case usageLimit(ProviderID, detail: String, manageURL: URL?)
    /// The account can't use the provider this way (plan, region, policy).
    case notEligible(ProviderID, detail: String)
    /// The request asked for something the model or route doesn't support.
    case unsupported(ProviderID, detail: String)
    /// The provider is temporarily unavailable; trying again later may work.
    case unavailable(ProviderID, detail: String)
    /// Any other HTTP failure, with the status and the body's message.
    case http(ProviderID, status: Int, detail: String)
    /// The response could not be understood.
    case malformedResponse(ProviderID, detail: String)
    /// No catalogue entry matches the requested model.
    case unknownModel(ModelRef)

    /// The provider the error came from.
    public var provider: ProviderID {
        switch self {
        case .notConnected(let provider), .signInRequired(let provider, _), .usageLimit(let provider, _, _),
            .notEligible(let provider, _), .unsupported(let provider, _), .unavailable(let provider, _),
            .http(let provider, _, _), .malformedResponse(let provider, _):
            provider
        case .unknownModel(let ref):
            ref.provider
        }
    }

    /// One line saying what went wrong.
    public var errorDescription: String? {
        let name = provider.displayName
        return switch self {
        case .notConnected: "\(name) isn't connected."
        case .signInRequired(_, let detail): "\(name) needs you to sign in again. \(detail)"
        case .usageLimit(_, let detail, _): "\(name) usage limit reached. \(detail)"
        case .notEligible(_, let detail): "\(name) can't be used with this account. \(detail)"
        case .unsupported(_, let detail): "\(name) doesn't support this request. \(detail)"
        case .unavailable(_, let detail): "\(name) is unavailable right now. \(detail)"
        case .http(_, let status, let detail): "\(name) answered HTTP \(status). \(detail)"
        case .malformedResponse(_, let detail): "\(name) sent a response Tag couldn't read. \(detail)"
        case .unknownModel(let ref): "No model \(ref) in the catalogue."
        }
    }

    /// What the user can do next.
    public var recoverySuggestion: String? {
        switch self {
        case .notConnected, .signInRequired:
            "Connect it with /model, then ^a."
        case .usageLimit(_, _, let url):
            url.map { "Manage usage: \($0.absoluteString), or switch models with /model." }
                ?? "Wait for the limit to reset, or switch models with /model."
        case .notEligible:
            "Use another provider or an API key: /model, then ^a."
        case .unavailable:
            "Try again in a moment."
        case .unknownModel:
            "Open /model to see the models you can use."
        case .unsupported, .http, .malformedResponse:
            nil
        }
    }
}
