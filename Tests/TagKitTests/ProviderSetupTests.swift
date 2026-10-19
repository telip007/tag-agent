import Foundation
import ModelKit
import Testing

@testable import Stipple
@testable import TagKit

@MainActor
struct ProviderSetupTests {
    /// The setup over a selection with nothing connected yet.
    private func setup(
        directory: URL = temporaryConfigDirectory(),
        offersProceed: Bool = false,
        signIn: (@MainActor (ProviderID) async throws -> Void)? = nil,
    ) async -> ProviderSetupState {
        let selection = makeSelection(directory: directory, connected: false, signIn: signIn)
        await selection.load()
        return ProviderSetupState(selection: selection, offersProceed: offersProceed)
    }

    @Test func masksAllButTheLastFourCharacters() {
        #expect(ProviderSetupState.masked("sk-or-v1-abcd1234") == "•••••••••••••1234")
        #expect(ProviderSetupState.masked("abc") == "•••")
        #expect(ProviderSetupState.masked("").isEmpty)
        #expect(ProviderSetupState.masked(String(repeating: "x", count: 100)).count == 28)
    }

    @Test func checksPastedKeys() {
        #expect(ProviderSetupState.problem(with: "") == "Paste a key first.")
        #expect(ProviderSetupState.problem(with: "sk one") != nil)
        #expect(ProviderSetupState.problem(with: "sk-or-v1-abc") == nil)
    }

    @Test func listsTheProvidersThenContinueDuringOnboarding() async {
        #expect(await setup().items == [.provider(.codex), .provider(.openCodeGo), .provider(.openRouter)])
        #expect(await setup(offersProceed: true).items.last == .proceed)
    }

    @Test func pastingAKeyConnectsTheProvider() async {
        let state = await setup(offersProceed: true)
        state.highlight(2)
        #expect(state.activate() == nil)
        #expect(state.phase == .key(.openRouter))
        state.type(" sk-or-v1-abcd ")
        state.deleteBackward()
        await state.saveKey()
        #expect(state.phase == .list)
        #expect(state.notice == "OpenRouter connected.")
        #expect(state.error == nil)
        #expect(state.selection.connected == [.openRouter])
        #expect(state.canProceed)
        #expect(state.items[state.highlighted] == .proceed)
        #expect(state.activate() == .proceed)
    }

    @Test func aBadKeyStaysWithAnError() async {
        let state = await setup()
        state.highlight(1)
        _ = state.activate()
        await state.saveKey()
        #expect(state.error == "Paste a key first.")
        state.type("two words")
        #expect(state.error == nil)
        await state.saveKey()
        #expect(state.error?.contains("no spaces") == true)
        #expect(state.phase == .key(.openCodeGo))
    }

    @Test func continuingNeedsAConnectedProvider() async {
        let state = await setup(offersProceed: true)
        state.highlight(99)
        #expect(state.items[state.highlighted] == .proceed)
        #expect(state.activate() == nil)
        #expect(state.error == "Connect a provider first.")
    }

    @Test func signingInWaitsForTheBrowser() async {
        let directory = temporaryConfigDirectory()
        let signIns = SignIns()
        let state = await setup(directory: directory) { provider in
            signIns.providers.append(provider)
            // The fake provider counts as connected once it has a credential.
            try CredentialStore(directory: directory, environment: [:]).setAPIKey("token", for: provider)
        }
        state.startSignIn(.codex)
        #expect(state.phase == .signingIn(.codex))
        await state.signIn(.codex)
        #expect(signIns.providers.contains(.codex))
        #expect(state.phase == .list)
        #expect(state.notice == "ChatGPT (Codex) connected.")

        let unfinished = await setup { _ in }
        await unfinished.signIn(.codex)
        #expect(unfinished.error == "ChatGPT (Codex) isn't connected yet. Try again.")
    }

    @Test func aFailedOrCancelledSignInGoesBackToTheList() async {
        let failing = await setup { _ in throw ProviderError.notEligible(.codex, detail: "No plan.") }
        await failing.signIn(.codex)
        #expect(failing.phase == .list)
        #expect(failing.error?.contains("No plan.") == true)

        let cancelled = await setup { _ in throw CancellationError() }
        await cancelled.signIn(.codex)
        #expect(cancelled.phase == .list && cancelled.error == nil)

        let waiting = await setup { _ in try await Task.sleep(for: .seconds(60)) }
        waiting.startSignIn(.codex)
        #expect(waiting.handle(KeyPress(key: .escape)).handled)
        #expect(waiting.phase == .list)
    }

    @Test func aProviderWhoseCatalogueFailsSaysSo() async throws {
        let directory = temporaryConfigDirectory()
        let credentials = CredentialStore(directory: directory, environment: [:])
        let failing = FakeProvider(
            id: .openRouter, failure: .http(.openRouter, status: 401, detail: "Bad key."), alwaysConnected: false,
            credentials: credentials)
        let selection = ModelSelection(
            registry: ProviderRegistry(providers: [failing]), settings: SettingsStore(directory: directory),
            credentials: credentials)
        let state = ProviderSetupState(selection: selection)
        _ = state.activate()
        state.type("sk-wrong")
        await state.saveKey()
        #expect(state.error?.contains("401") == true)
        #expect(state.notice == nil)
    }

    @Test func keysMoveTypeAndClose() async {
        let state = await setup()
        #expect(state.handle(KeyPress(key: .downArrow)).handled)
        #expect(state.handle(KeyPress(key: "j")).handled)
        #expect(state.highlighted == 2)
        #expect(state.handle(KeyPress(key: "k")).handled)
        #expect(state.handle(KeyPress(key: .upArrow)).handled)
        #expect(state.highlighted == 0)
        #expect(state.handle(KeyPress(key: .tab)) == (false, nil))
        #expect(state.handle(KeyPress(key: .escape)).action == .close)
        #expect(state.handle(KeyPress(key: .return, phase: .up)) == (false, nil))

        state.highlight(1)
        _ = state.handle(KeyPress(key: .return))
        #expect(state.phase == .key(.openCodeGo))
        _ = state.handle(KeyPress(key: "s", characters: "sk-abcd"))
        _ = state.handle(KeyPress(key: .backspace))
        #expect(state.key == "sk-abc")
        #expect(state.handle(KeyPress(key: .leftArrow)) == (false, nil))
        _ = state.handle(KeyPress(key: "u", modifiers: .control))
        #expect(state.key.isEmpty)
        _ = state.handle(KeyPress(key: .escape))
        #expect(state.phase == .list)
        #expect(state.handle(KeyPress(key: "x")) == (false, nil))
    }
}
