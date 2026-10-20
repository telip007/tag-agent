import CryptoKit
import Foundation

/// A Proof Key for Code Exchange pair (RFC 7636): the secret verifier kept
/// by Tag Agent and the challenge sent with the authorization request.
struct PKCE: Sendable, Equatable {
    /// The secret sent with the code exchange.
    var verifier: String
    /// The base64url SHA-256 of ``verifier``, without padding.
    var challenge: String

    /// A fresh pair from 32 random bytes.
    static func make() -> Self {
        Self(verifier: Base64URL.randomValue())
    }

    /// The pair for `verifier`.
    init(verifier: String) {
        self.verifier = verifier
        self.challenge = Base64URL.encode(Data(SHA256.hash(data: Data(verifier.utf8))))
    }
}

/// Base64url without padding (RFC 4648 §5), as OAuth and JWTs use it.
enum Base64URL {
    /// Encodes `data`.
    static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacing("+", with: "-")
            .replacing("/", with: "_")
            .replacing("=", with: "")
    }

    /// Decodes `text`, padded or not; `nil` when it isn't base64url.
    static func decode(_ text: some StringProtocol) -> Data? {
        var base64 = String(text).replacing("-", with: "+").replacing("_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }

    /// A fresh random value of `count` bytes from the system's secure
    /// generator, encoded: for `state`, `nonce` and PKCE verifiers.
    static func randomValue(count: Int = 32) -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        return encode(Data(bytes))
    }
}
