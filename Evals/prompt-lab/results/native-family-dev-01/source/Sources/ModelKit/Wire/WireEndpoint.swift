public import Foundation

/// Where and how a wire format adapter sends its requests.
public struct WireEndpoint: Sendable {
    /// The full URL requests are posted to.
    public var url: URL
    /// The model id sent in the request.
    public var model: String
    /// The provider, for errors.
    public var provider: ProviderID
    /// Headers for each request, authorization included; read per request so
    /// tokens can be refreshed.
    public var headers: @Sendable () async throws -> [String: String]
    /// What sends the requests.
    public var transport: any HTTPTransport

    /// Creates an endpoint.
    ///
    /// - Parameters:
    ///   - url: The full URL requests are posted to.
    ///   - model: The model id sent in the request.
    ///   - provider: The provider, for errors.
    ///   - headers: Headers for each request, authorization included.
    ///   - transport: What sends the requests.
    public init(
        url: URL,
        model: String,
        provider: ProviderID,
        headers: @escaping @Sendable () async throws -> [String: String],
        transport: any HTTPTransport = URLSessionTransport(),
    ) {
        self.url = url
        self.model = model
        self.provider = provider
        self.headers = headers
        self.transport = transport
    }

    /// A streaming JSON `POST` of `body` with the endpoint's headers.
    ///
    /// - Throws: What ``headers`` throws.
    public func request(body: Data) async throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(TagUserAgent.value, forHTTPHeaderField: "User-Agent")
        for (name, value) in try await headers() {
            request.setValue(value, forHTTPHeaderField: name)
        }
        return request
    }
}
