import Foundation
import ModelKit
import Testing

@testable import TagKit

@MainActor
struct ModelSelectionTests {
    @Test func loadsTheConnectedProvidersAndTheirModels() async {
        let selection = makeSelection()
        #expect(selection.catalogue == nil)
        await selection.load()
        #expect(selection.connected == [.codex, .openCodeGo, .openRouter])
        #expect(selection.catalogue?.entries == Models.all)
        #expect(!selection.isLoading)
    }

    @Test func selectingAModelRemembersItAndItsEffort() async throws {
        let directory = temporaryConfigDirectory()
        let selection = makeSelection(directory: directory)
        try await selection.select(Models.codex, effort: "high")
        #expect(selection.current?.entry == Models.codex)
        #expect(selection.current?.effort == "high")
        try await selection.select(Models.kimi, effort: "high")
        #expect(selection.current?.effort == nil)
        #expect(selection.recent == [Models.kimi.ref, Models.codex.ref])

        let settings = SettingsStore(directory: directory).load()
        #expect(settings.lastModel == Models.kimi.ref)
        #expect(settings.effort(for: Models.codex.ref) == "high")
        #expect(makeSelection(directory: directory).recent == [Models.kimi.ref, Models.codex.ref])
    }

    @Test func aModelItsProviderCantServeIsNotSelected() async {
        let selection = makeSelection()
        var unknown = Models.kimi
        unknown.ref.model = "gone"
        await #expect(throws: ProviderError.self) {
            try await selection.select(unknown, effort: nil)
        }
        #expect(selection.current == nil)
        let empty = ModelSelection(
            registry: ProviderRegistry(providers: []), settings: SettingsStore(directory: temporaryConfigDirectory()))
        await #expect(throws: ProviderError.unknownModel(Models.kimi.ref)) {
            try await empty.select(Models.kimi, effort: nil)
        }
    }

    @Test func restoresTheLastModelWithItsEffort() async throws {
        let directory = temporaryConfigDirectory()
        try await makeSelection(directory: directory).select(Models.gptRouter, effort: "low")

        let next = makeSelection(directory: directory)
        #expect(await next.restoreLastModel())
        #expect(next.current?.entry == Models.gptRouter)
        #expect(next.current?.effort == "low")

        let loaded = makeSelection(directory: directory)
        await loaded.load()
        #expect(await loaded.restoreLastModel())
    }

    @Test func nothingToRestoreOnAFirstStartOrWhenTheModelIsGone() async throws {
        #expect(await !makeSelection().restoreLastModel())

        let directory = temporaryConfigDirectory()
        try SettingsStore(directory: directory).update {
            $0.use(ModelRef(provider: .codex, model: "gone"), effort: nil)
        }
        #expect(await !makeSelection(directory: directory).restoreLastModel())

        let offline = temporaryConfigDirectory()
        try await makeSelection(directory: offline).select(Models.kimi, effort: nil)
        #expect(await !makeSelection(directory: offline, connected: false).restoreLastModel())
    }

    @Test func offersTheRememberedEffortElseMediumElseTheMiddle() async throws {
        let selection = makeSelection()
        #expect(selection.effort(for: Models.codex) == "medium")
        #expect(selection.effort(for: Models.codexMini) == "high")
        #expect(selection.effort(for: Models.kimi) == nil)
        try await selection.select(Models.codexMini, effort: "minimal")
        #expect(selection.effort(for: Models.codexMini) == "minimal")
        #expect(ModelSelection.defaultEffort(of: ["low", "high"]) == "high")
        #expect(ModelSelection.defaultEffort(of: []) == nil)
    }

    @Test func quickSwitchesToAnExactModel() async {
        let selection = makeSelection()
        #expect(await selection.quickSwitch("go/kimi-k3") == Models.kimi)
        #expect(selection.current?.entry == Models.kimi)
        #expect(await selection.quickSwitch("OpenRouter/DeepSeek/DeepSeek-V4.1-Flash") == Models.deepseek)
        #expect(await selection.quickSwitch("codex/gpt-5.5-codex")?.ref == Models.codex.ref)
        #expect(selection.current?.effort == "medium")
    }

    @Test func quickSwitchLeavesTheRestToThePicker() async {
        let selection = makeSelection()
        #expect(await selection.quickSwitch("kimi") == nil)
        #expect(await selection.quickSwitch("go/kimi") == nil)
        #expect(await selection.quickSwitch("nope/kimi-k3") == nil)
        #expect(selection.current == nil)
    }

    @Test func theChatGPTPlanNoticeShowsOnce() async throws {
        let directory = temporaryConfigDirectory()
        let selection = makeSelection(directory: directory)
        try await selection.select(Models.kimi, effort: nil)
        #expect(!selection.isChatGPTWelcomeDue)
        try await selection.select(Models.codex, effort: nil)
        #expect(selection.isChatGPTWelcomeDue)
        selection.dismissChatGPTWelcome()
        #expect(!selection.isChatGPTWelcomeDue)
        try await selection.select(Models.codexMini, effort: nil)
        #expect(!selection.isChatGPTWelcomeDue)
        let later = makeSelection(directory: directory)
        try await later.select(Models.codex, effort: nil)
        #expect(!later.isChatGPTWelcomeDue)
    }

    @Test func savingAKeyConnectsTheProvider() async throws {
        let directory = temporaryConfigDirectory()
        let selection = makeSelection(directory: directory, connected: false)
        await selection.load()
        #expect(selection.connected.isEmpty)
        try await selection.saveAPIKey("sk-test-1234", for: .openRouter)
        #expect(selection.connected == [.openRouter])
        #expect(selection.catalogue?.entries == [Models.gptRouter, Models.deepseek])
        #expect(CredentialStore(directory: directory, environment: [:]).load().apiKeys["openrouter"] == "sk-test-1234")
    }

    @Test func signingInRunsTheInjectedSignInThenReloads() async throws {
        let signedIn = SignIns()
        let selection = makeSelection { signedIn.providers.append($0) }
        try await selection.signIn(.codex)
        #expect(signedIn.providers == [.codex])
        #expect(selection.catalogue != nil)
        await #expect(throws: SignInUnavailable.self) {
            try await makeSelection().signIn(.codex)
        }
        #expect(SignInUnavailable().localizedDescription.contains("isn't available"))
    }
}
