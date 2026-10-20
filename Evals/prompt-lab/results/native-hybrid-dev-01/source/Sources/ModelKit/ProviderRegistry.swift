import Foundation

/// The providers Tag Agent knows, and the models of the connected ones.
public struct ProviderRegistry: Sendable {
    /// Every provider, in display order.
    public let providers: [any Provider]

    /// Creates a registry.
    ///
    /// - Parameter providers: The providers, in display order.
    public init(providers: [any Provider]) {
        self.providers = providers
    }

    /// The provider with `id`, if registered.
    public func provider(_ id: ProviderID) -> (any Provider)? {
        providers.first { $0.id == id }
    }

    /// The providers with credentials.
    public func connected() async -> [ProviderID] {
        var ids: [ProviderID] = []
        for provider in providers where await provider.isConnected() {
            ids.append(provider.id)
        }
        return ids
    }

    /// The models of every connected provider, fetched in parallel, in
    /// provider order. A provider whose catalogue fails is reported in
    /// `failures` instead.
    public func catalogue() async -> Catalogue {
        let results = await withTaskGroup(of: (Int, Result<[ModelEntry], any Error>?).self) { group in
            for (index, provider) in providers.enumerated() {
                group.addTask {
                    guard await provider.isConnected() else {
                        return (index, nil)
                    }
                    do {
                        return (index, .success(try await provider.models()))
                    } catch {
                        return (index, .failure(error))
                    }
                }
            }
            var results: [(Int, Result<[ModelEntry], any Error>?)] = []
            for await result in group {
                results.append(result)
            }
            return results.sorted { $0.0 < $1.0 }
        }
        var catalogue = Catalogue()
        for (index, result) in results {
            switch result {
            case .success(let entries): catalogue.entries += entries
            case .failure(let error): catalogue.failures[providers[index].id] = error.localizedDescription
            case nil: break
            }
        }
        return catalogue
    }

    /// The catalogue entry for `ref`.
    ///
    /// - Throws: ``ProviderError/unknownModel(_:)`` when the provider doesn't
    ///   list it, or the provider's error.
    public func entry(for ref: ModelRef) async throws -> ModelEntry {
        guard let provider = provider(ref.provider) else {
            throw ProviderError.unknownModel(ref)
        }
        guard let entry = try await provider.models().first(where: { $0.ref == ref }) else {
            throw ProviderError.unknownModel(ref)
        }
        return entry
    }
}

/// The models of the connected providers, and the providers whose
/// catalogue couldn't be read.
public struct Catalogue: Sendable {
    /// Every model, in provider order.
    public var entries: [ModelEntry] = []
    /// Why a provider's models are missing, by provider.
    public var failures: [ProviderID: String] = [:]

    /// An empty catalogue.
    public init() {}
}
