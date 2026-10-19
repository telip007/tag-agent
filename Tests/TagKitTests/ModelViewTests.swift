import Foundation
import ModelKit
import Testing

@testable import Stipple
@testable import TagKit

@MainActor
struct ModelViewTests {
    private func picker(query: String = "", catalogue: Catalogue? = Models.catalogue) -> ModelPickerState {
        let state = ModelPickerState(
            query: query, catalogue: catalogue, current: Models.codex.ref,
            recent: [Models.codex.ref, Models.kimi.ref]
        ) { ModelSelection.defaultEffort(of: $0.reasoningEfforts) }
        state.rowLimit = 12
        return state
    }

    private func lines(_ view: some View, width: Int = 80) -> [String] {
        plainText(view, width: width).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    @Test func thePickerListsRecentThenEachProvider() {
        let screen = lines(ModelPicker(state: picker(), width: 72) { _ in })
        #expect(screen[0].hasPrefix("╭─ model ─") && screen[0].count == 72)
        #expect(screen[1].hasPrefix("│ ›  search models"))
        #expect(screen[3].hasPrefix("│ recent ") && screen[3].hasSuffix(" │"))
        #expect(screen[4].hasPrefix("│ ● GPT-5.5 Codex") && screen[4].contains("chatgpt (codex)"))
        #expect(screen[4].hasSuffix("included │"))
        #expect(screen[5].hasPrefix("│   Kimi K3") && screen[5].contains("opencode go"))
        #expect(
            screen.contains { $0.hasPrefix("│   GPT-5.5  ") && $0.contains("400k ctx") && $0.contains("$1.25 / $10") })
        #expect(screen.contains { $0.contains("DeepSeek V4.1 Flash") && $0.contains("1M ctx") && $0.contains("free") })
        #expect(screen.contains { $0.hasPrefix("│ reasoning ◂ medium ▸ ") })
        #expect(screen.contains { $0.hasPrefix("│ ↵ use · ←→ effort · ^a add provider · esc close") })
        #expect(Set(screen.filter { !$0.isEmpty }.map(\.count)) == [72])
    }

    @Test func theHighlightedRowIsTinted() {
        let rendered = Stipple.renderToString(ModelPicker(state: picker(), width: 72) { _ in }, width: 80)
        #expect(rendered.contains("48;2;58;62;80m"))
        #expect(rendered.contains("38;2;227;179;65m●"))
    }

    @Test func aModelWithoutEffortsHasNoEffortLine() {
        let state = picker(query: "kimi")
        let screen = plainText(ModelPicker(state: state, width: 72) { _ in })
        #expect(!screen.contains("reasoning"))
        #expect(!screen.contains("←→"))
        #expect(screen.contains("│ › kimi"))
    }

    @Test func thePickerSaysWhenItLoadsOrFindsNothing() {
        let loading = plainText(ModelPicker(state: picker(catalogue: nil), width: 72) { _ in })
        #expect(loading.contains("loading models…") && loading.contains("loading…"))
        let none = plainText(ModelPicker(state: picker(query: "zzz"), width: 72) { _ in })
        #expect(none.contains("No model matches “zzz”."))
        let empty = plainText(ModelPicker(state: picker(catalogue: Catalogue()), width: 72) { _ in })
        #expect(empty.contains("No models yet. ^a connects a provider."))
        let state = picker()
        state.error = "OpenRouter isn't connected."
        #expect(plainText(ModelPicker(state: state, width: 72) { _ in }).contains("✗ OpenRouter isn't connected."))
    }

    @Test func aFailedCatalogueShowsItsError() {
        var catalogue = Models.catalogue
        catalogue.failures[.openCodeGo] = "OpenCode Go answered HTTP 401."
        let screen = plainText(ModelPicker(state: picker(catalogue: catalogue), width: 72) { _ in })
        #expect(screen.contains("✗ opencode go: OpenCode Go answered HTTP 401."))
    }

    @Test func connectingListsEachProviderAndHowItConnects() async throws {
        let selection = makeSelection(connected: false)
        try await selection.saveAPIKey("sk-1234", for: .openRouter)
        let state = ProviderSetupState(selection: selection, offersProceed: true)
        let screen = plainText(ProviderSetup(state: state, width: 64) { _ in })
        #expect(screen.contains("╭─ connect a provider ─"))
        #expect(screen.contains("│ › ChatGPT (Codex)     Continue with ChatGPT"))
        #expect(screen.contains("│   OpenCode Go         paste an API key"))
        #expect(screen.contains("│   OpenRouter          ✓ connected"))
        #expect(screen.contains("│   Continue →"))
        #expect(screen.contains("↵ connect · esc back"))
    }

    @Test func pastingAKeyShowsWhereToGetOneAndMasksIt() async {
        let selection = makeSelection(connected: false)
        await selection.load()
        let state = ProviderSetupState(selection: selection)
        state.highlight(1)
        _ = state.activate()
        state.type("sk-secret-9876")
        let screen = plainText(ProviderSetup(state: state, width: 64) { _ in })
        #expect(screen.contains("╭─ connect OpenCode Go ─"))
        #expect(screen.contains("Get an API key at https://example.com/keys"))
        #expect(screen.contains("or set FAKE_KEY."))
        #expect(screen.contains("› ••••••••••9876"))
        #expect(!screen.contains("secret"))
        #expect(screen.contains("↵ save · esc back"))
    }

    @Test func signingInWaitsForTheBrowser() {
        let selection = makeSelection(connected: false) { _ in try await Task.sleep(for: .seconds(60)) }
        let state = ProviderSetupState(selection: selection)
        state.startSignIn(.codex)
        let screen = plainText(ProviderSetup(state: state, width: 64) { _ in })
        #expect(screen.contains("Continue with ChatGPT"))
        #expect(screen.contains("Finish signing in in your browser…"))
        #expect(screen.contains("esc cancel"))
        state.cancel()
        #expect(state.phase == .list)
    }

    @Test func theOnboardingWelcomes() {
        let view = OnboardingView(selection: makeSelection(connected: false))
            .environment(\.terminalSize, Size(width: 90, height: 30))
        let screen = plainText(view, width: 90)
        #expect(screen.contains("╭─ tag ─"))
        #expect(screen.contains("Welcome to Tag Agent."))
        #expect(screen.contains("plan, OpenCode Go or OpenRouter."))
        #expect(screen.contains("↵ get started · ^c quit"))
        #expect(OnboardingView.renderOptions.alternateScreen && !OnboardingView.renderOptions.exitOnCtrlC)
    }

    @Test func theOnboardingSaysWhenTheLastModelIsGone() throws {
        let directory = temporaryConfigDirectory()
        try SettingsStore(directory: directory).update { $0.use(Models.kimi.ref, effort: nil) }
        let view = OnboardingView(selection: makeSelection(directory: directory))
            .environment(\.terminalSize, Size(width: 90, height: 30))
        #expect(plainText(view, width: 90).contains("The model you used last isn't available any more."))
    }

    @Test func failedCallsShowWhatToDo() {
        let block = TranscriptBlock(
            id: 0,
            content: .failure(
                message: "ChatGPT (Codex) usage limit reached. Weekly.",
                recovery: "Manage usage: https://chatgpt.com/usage, or switch models with /model."))
        let text = plainText(BlockView(block: block, isExpanded: false, isSelected: false))
        #expect(
            text
                == "\n  ✗ ChatGPT (Codex) usage limit reached. Weekly.\n    Manage usage: https://chatgpt.com/usage, or switch models with /model."
        )
        #expect(!block.isExpandable)
        #expect(block.plainText.hasSuffix("/model."))
    }
}

@MainActor
struct ModelWorkspaceTests {
    private func workspace(_ selection: ModelSelection, width: Int = 110) -> String {
        let session = ChatSession()
        session.handle(.status(StatusLine(directory: URL(filePath: "/tmp"), model: ModelDescription(name: "Old"))))
        let agent = Terminal([]).agent(model: ScriptedModel([]))
        let view = ChatView(session: session, agent: agent, selection: selection, copy: { _ in })
            .frame(height: 24)
            .environment(\.terminalSize, Size(width: width, height: 24))
        return plainText(view, width: width)
    }

    @Test func thePanelNamesTheModelItsEffortAndTheChatGPTPlan() async throws {
        let selection = makeSelection()
        try await selection.select(Models.codex, effort: "high")
        selection.dismissChatGPTWelcome()
        let screen = workspace(selection)
        #expect(screen.contains("│ GPT-5.5 Codex"))
        #expect(screen.contains("│ chatgpt (codex) · high"))
        #expect(screen.contains("│ Using ChatGPT plan"))
        #expect(!screen.contains("You're using your ChatGPT plan"))
    }

    @Test func otherProvidersDontMentionThePlan() async throws {
        let selection = makeSelection()
        try await selection.select(Models.kimi, effort: nil)
        let screen = workspace(selection)
        #expect(screen.contains("│ Kimi K3"))
        #expect(screen.contains("│ opencode go"))
        #expect(!screen.contains("ChatGPT plan"))
        #expect(workspace(makeSelection()).contains("│ Old"))
    }

    @Test func theFirstChatGPTPlanModelShowsTheNoticeOnce() async throws {
        let selection = makeSelection()
        try await selection.select(Models.codex, effort: nil)
        let screen = workspace(selection)
        #expect(screen.contains("╭─ ChatGPT plan ─"))
        #expect(screen.contains("You're using your ChatGPT plan"))
        #expect(screen.contains("↵ Got it"))
    }

    @Test func thePaletteOffersModelCommands() {
        #expect(PaletteCommand.switchModel.rawValue == "Switch model")
        #expect(PaletteCommand.switchModel.key == "/model")
        #expect(PaletteCommand.connectProvider.rawValue == "Connect a provider")
    }
}
