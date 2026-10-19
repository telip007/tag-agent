import ModelKit
import Testing

@testable import TagKit

struct ModelSearchTests {
    private func rows(_ query: String, recent: [ModelRef] = [], failures: [ProviderID: String] = [:]) -> [PickerRow] {
        PickerList.rows(
            models: Models.all.map(SearchableModel.init), query: query, recent: recent, failures: failures)
    }

    private func names(_ rows: [PickerRow]) -> [String] {
        rows.compactMap(\.entry?.name)
    }

    @Test func wordPrefixesBeatSubstringsBeatSubsequences() {
        let kimi = SearchableModel(Models.kimi)
        #expect(kimi.score(["kim"]) == 3)
        #expect(kimi.score(["i-k"]) == 2)
        #expect(kimi.score(["kk3"]) == 1)
        #expect(kimi.score(["go", "kimi"]) == 6)
        #expect(kimi.score(["gpt"]) == nil)
        #expect(kimi.score([]) == 0)
    }

    @Test func theWholeNameOrIdRanksFirst() {
        let longer = ModelEntry(
            ref: ModelRef(provider: .openRouter, model: "deepseek/deepseek-v4.1-flash-1017"),
            name: "DeepSeek V4.1 Flash 1017", format: .openRouter)
        let exact = ModelEntry(
            ref: ModelRef(provider: .openRouter, model: "deepseek/deepseek-v4.1-flash"),
            name: "DeepSeek V4.1 Flash", format: .openRouter)
        let rows = PickerList.rows(
            models: [longer, exact].map(SearchableModel.init), query: "deepseek v4.1 flash", recent: [], failures: [:])
        #expect(names(rows) == ["DeepSeek V4.1 Flash", "DeepSeek V4.1 Flash 1017"])
        #expect(SearchableModel(exact).score(SearchableModel.tokens(of: "deepseek/deepseek-v4.1-flash")) != nil)
    }

    @Test func providerNamesAndAliasesAreWordsToo() {
        let kimi = SearchableModel(Models.kimi)
        #expect(kimi.words.contains("opencode") && kimi.words.contains("go"))
        #expect(SearchableModel(Models.codex).score(["chatgpt"]) == 3)
    }

    @Test func tokensSplitAtSpacesAndSlashes() {
        #expect(SearchableModel.tokens(of: " Go  KIMI ") == ["go", "kimi"])
        #expect(SearchableModel.tokens(of: "openrouter/deepseek/v4") == ["openrouter", "deepseek", "v4"])
        #expect(SearchableModel.tokens(of: "  ").isEmpty)
    }

    @Test func subsequencesKeepTheirOrder() {
        #expect(SearchableModel.isSubsequence("dsf", of: "deepseek flash"))
        #expect(!SearchableModel.isSubsequence("fsd", of: "deepseek flash"))
        #expect(SearchableModel.isSubsequence("", of: "x"))
    }

    @Test func anEmptySearchListsRecentThenEveryProvider() {
        let list = rows("", recent: [Models.kimi.ref, Models.codex.ref])
        #expect(list.first == .header("recent"))
        #expect(list[1] == .model(Models.kimi, isRecent: true))
        #expect(list[2] == .model(Models.codex, isRecent: true))
        let headers = list.compactMap { if case .header(let title) = $0 { title } else { nil } }
        #expect(headers == ["recent", "chatgpt (codex)", "opencode go", "openrouter"])
        #expect(names(list).count == Models.all.count + 2)
    }

    @Test func goKimiFindsKimiOnOpenCodeGo() {
        #expect(names(rows("go kimi")) == ["Kimi K3"])
        #expect(names(rows("go/kimi")) == ["Kimi K3"])
    }

    @Test func aSearchPutsTheBestProviderAndModelFirst() {
        // "deepseek" is a word of DeepSeek's name; only OpenRouter has it.
        #expect(names(rows("deepseek")) == ["DeepSeek V4.1 Flash"])
        // Every GPT-5.5 has "openai" and "gpt" as words: equal scores keep the catalogue's order.
        #expect(names(rows("openai gpt")) == ["GPT-5.5 Codex", "GPT-5.5 mini", "GPT-5.5"])
        // Only OpenRouter's names it, so its models lead.
        let router = rows("router gpt")
        #expect(router.first == .header("openrouter"))
    }

    @Test func recentModelsAreFilteredToo() {
        let list = rows("kimi", recent: [Models.codex.ref, Models.kimi.ref])
        #expect(list.prefix(2) == [.header("recent"), .model(Models.kimi, isRecent: true)])
    }

    @Test func failuresLeadAnEmptySearchOnly() {
        let failures: [ProviderID: String] = [.openRouter: "OpenRouter answered HTTP 401."]
        #expect(rows("", failures: failures).first == .failure(.openRouter, "OpenRouter answered HTTP 401."))
        #expect(!rows("kimi", failures: failures).contains(.failure(.openRouter, "OpenRouter answered HTTP 401.")))
    }

    @Test(arguments: [
        (Pricing.included, "included"),
        (.free, "free"),
        (.perMillion(input: 1.25, output: 10), "$1.25 / $10"),
        (.perMillion(input: 0.075, output: 0.3), "$0.075 / $0.3"),
        (.unknown, ""),
    ])
    func formatsPrices(pricing: Pricing, expected: String) {
        #expect(PickerList.price(pricing) == expected)
    }

    @Test func formatsContextWindows() {
        #expect(PickerList.context(Models.codex) == "400k ctx")
        #expect(PickerList.context(Models.deepseek) == "1M ctx")
        var unknown = Models.kimi
        unknown.contextLength = nil
        #expect(PickerList.context(unknown).isEmpty)
    }
}
