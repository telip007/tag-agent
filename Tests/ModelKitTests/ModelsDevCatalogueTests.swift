import Foundation
import Testing

@testable import ModelKit

struct ModelsDevCatalogueTests {
    /// A slice of models.dev's api.json, odd shapes included.
    static let json = #"""
        {
          "opencode-go": {
            "id": "opencode-go", "npm": "@ai-sdk/openai-compatible", "env": ["OPENCODE_API_KEY"],
            "models": {
              "kimi-k3": {
                "id": "kimi-k3", "name": "Kimi K3", "reasoning": true,
                "reasoning_options": [{"type": "toggle"}, {"type": "effort", "values": ["max"]}],
                "interleaved": {"field": "reasoning_content"},
                "limit": {"context": 1048576, "output": 131072}, "cost": {"input": 3, "output": 15},
                "provider": {"api": "https://opencode.ai/inference/go/openai/v1"}
              },
              "claude-haiku-5-5": {
                "id": "claude-haiku-5-5", "name": "Claude Haiku 5.5", "reasoning": true,
                "reasoning_options": [{"type": "effort", "values": ["low", "high"]}], "interleaved": null,
                "limit": {"context": 1000000, "output": 128000}, "cost": {"input": 0.1, "output": 0.5},
                "provider": {"npm": "@ai-sdk/anthropic"}
              },
              "gemini-4-argon-contributor": {
                "name": "Gemini 4 Argon", "reasoning": true, "provider": {"npm": "@ai-sdk/google"}
              },
              "gpt-6-luna": {"name": "GPT-6 Luna", "provider": {"npm": "@ai-sdk/openai"}, "interleaved": true},
              "beam-free": {"name": "Beam Free", "cost": {"input": 0, "output": 0}},
              "old-model": {"name": "Old", "status": "deprecated", "reasoning_options": "weird"},
              "broken": {"title": "no name"}
            }
          },
          "other": {"models": 5},
          "junk": 7
        }
        """#

    private static func temporaryCache() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "tag-models-dev-\(UUID().uuidString)/cache/models-dev.json")
    }

    @Test func decodesWhatItCanAndSkipsTheRest() throws {
        let providers = try #require(ModelsDevCatalogue.decode(Data(Self.json.utf8)))
        let opencode = try #require(providers["opencode-go"])
        #expect(providers["other"]?.models.isEmpty == true)
        #expect(providers["junk"] == nil)
        #expect(opencode.models["broken"] == nil)
        let kimi = try #require(opencode.models["kimi-k3"])
        #expect(
            kimi
                == ModelsDevModel(
                    name: "Kimi K3", contextLength: 1_048_576, outputLimit: 131_072, inputCost: 3, outputCost: 15,
                    reasoning: true, reasoningEfforts: ["max"], interleavedField: "reasoning_content"))
        #expect(opencode.models["gpt-6-luna"]?.interleavedField == "reasoning_content")
        #expect(opencode.models["old-model"]?.deprecated == true)
        #expect(opencode.models["old-model"]?.reasoningEfforts.isEmpty == true)
        #expect(opencode.models["beam-free"]?.isFree == true)
        #expect(kimi.isFree == false)
        #expect(opencode.format(of: "kimi-k3") == .chatCompletions)
        #expect(opencode.format(of: "claude-haiku-5-5") == .anthropicMessages)
        #expect(opencode.format(of: "gemini-4-argon-contributor") == .gemini)
        #expect(opencode.format(of: "gpt-6-luna") == .responses)
        #expect(opencode.format(of: "missing") == nil)
    }

    @Test func fetchesOnceAndCachesTheJSON() async throws {
        let cache = Self.temporaryCache()
        let transport = FakeTransport(body: Self.json)
        let catalogue = ModelsDevCatalogue(cacheURL: cache, transport: transport)
        #expect(await catalogue.provider("opencode-go")?.models["kimi-k3"]?.name == "Kimi K3")
        #expect(await catalogue.provider("missing") == nil)
        #expect(transport.requests.count == 1)
        #expect(transport.requests.first?.url == ModelsDevCatalogue.sourceURL)
        #expect(transport.requests.first?.value(forHTTPHeaderField: "User-Agent") == TagUserAgent.value)
        #expect(try SecureFile.read(cache) == Data(Self.json.utf8))

        let offline = FakeTransport { _ in nil }
        let again = ModelsDevCatalogue(cacheURL: cache, transport: offline)
        #expect(await again.provider("opencode-go") != nil)
        #expect(offline.requests.isEmpty)
    }

    @Test func fallsBackToAStaleCacheWhenTheFetchFails() async throws {
        let cache = Self.temporaryCache()
        try SecureFile.write(Data(Self.json.utf8), to: cache)
        let later = Date().addingTimeInterval(2 * 24 * 60 * 60)
        let failing = FakeTransport(status: 500, body: "down")
        let catalogue = ModelsDevCatalogue(cacheURL: cache, transport: failing, now: { later })
        #expect(await catalogue.provider("opencode-go")?.models.count == 6)
        #expect(failing.requests.count == 1)

        let empty = ModelsDevCatalogue(cacheURL: Self.temporaryCache(), transport: FakeTransport { _ in nil })
        #expect(await empty.provider("opencode-go") == nil)
    }

    @Test func refreshesAStaleCache() async throws {
        let cache = Self.temporaryCache()
        try SecureFile.write(Data(#"{"opencode-go": {"models": {}}}"#.utf8), to: cache)
        let later = Date().addingTimeInterval(2 * 24 * 60 * 60)
        let catalogue = ModelsDevCatalogue(cacheURL: cache, transport: FakeTransport(body: Self.json), now: { later })
        #expect(await catalogue.provider("opencode-go")?.models.count == 6)
    }
}
