import Testing

@testable import ModelKit

struct ModelRefTests {
    @Test func parsesProviderAndModelAtTheFirstSlash() {
        #expect(
            ModelRef(parsing: "openrouter/deepseek/deepseek-v4.1-flash")
                == ModelRef(provider: .openRouter, model: "deepseek/deepseek-v4.1-flash"))
        #expect(ModelRef(parsing: " go/kimi-k3 ") == ModelRef(provider: .openCodeGo, model: "kimi-k3"))
        #expect(ModelRef(parsing: "Codex/gpt-6.1-sol")?.provider == .codex)
    }

    @Test func rejectsUnknownProvidersAndEmptyModels() {
        #expect(ModelRef(parsing: "nope/model") == nil)
        #expect(ModelRef(parsing: "codex/") == nil)
        #expect(ModelRef(parsing: "kimi-k3") == nil)
    }
}
