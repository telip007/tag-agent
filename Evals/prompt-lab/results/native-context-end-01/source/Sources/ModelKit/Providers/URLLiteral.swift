import Foundation

extension URL {
    /// A URL from a literal known to be valid, such as an API's address.
    init(validLiteral literal: StaticString) {
        guard let url = URL(string: "\(literal)") else {
            preconditionFailure("Not a URL: \(literal)")
        }
        self = url
    }
}
