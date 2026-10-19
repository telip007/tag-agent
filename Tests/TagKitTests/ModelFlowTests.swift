import Foundation
import ModelKit
import Testing

@testable import Stipple
@testable import TagKit

@MainActor
struct ModelFlowTests {
    private func loadedFlow(isOnboarding: Bool = false) async -> ModelFlow {
        let selection = makeSelection()
        await selection.load()
        return ModelFlow(selection: selection, isOnboarding: isOnboarding)
    }

    private func picker(_ flow: ModelFlow) -> ModelPickerState? {
        if case .picker(let picker) = flow.screen { picker } else { nil }
    }

    private func setup(_ flow: ModelFlow) -> ProviderSetupState? {
        if case .connect(let setup) = flow.screen { setup } else { nil }
    }

    @Test func thePickerOpensWithTheTextAndClosesWithEscape() async {
        let flow = await loadedFlow()
        #expect(!flow.isOpen)
        flow.openPicker(query: "kimi")
        #expect(picker(flow)?.query == "kimi")
        #expect(picker(flow)?.highlightedEntry == Models.kimi)
        #expect(flow.handle(KeyPress(key: .escape)))
        #expect(!flow.isOpen)
        #expect(!flow.handle(KeyPress(key: "x")))
    }

    @Test func connectingFromThePickerGoesBackToIt() async {
        let flow = await loadedFlow()
        flow.openPicker()
        #expect(flow.handle(KeyPress(key: "a", modifiers: .control)))
        #expect(setup(flow) != nil)
        #expect(flow.handle(KeyPress(key: .escape)))
        #expect(picker(flow) != nil)

        flow.close()
        flow.openConnect()
        flow.perform(SetupAction.close)
        #expect(!flow.isOpen)
    }

    @Test func onboardingGoesBetweenConnectingAndPicking() async {
        let flow = await loadedFlow(isOnboarding: true)
        flow.openConnect()
        #expect(setup(flow)?.offersProceed == true)
        flow.perform(SetupAction.proceed)
        #expect(picker(flow) != nil)
        flow.perform(PickerAction.close)
        #expect(setup(flow) != nil)
        flow.perform(SetupAction.close)
        #expect(!flow.isOpen)
    }

    @Test func usingAModelSwitchesAndCloses() async {
        let flow = await loadedFlow()
        let chosen = SignIns()
        flow.onChosen = { chosen.providers.append(.openCodeGo) }
        flow.openPicker(query: "kimi")
        await flow.use(Models.kimi, effort: nil)
        #expect(flow.selection.current?.entry == Models.kimi)
        #expect(!flow.isOpen)
        #expect(chosen.providers == [.openCodeGo])
    }

    @Test func aModelThatCantBeUsedLeavesThePickerOpenWithTheError() async {
        let flow = await loadedFlow()
        flow.openPicker()
        var gone = Models.kimi
        gone.ref.model = "gone"
        await flow.use(gone, effort: nil)
        #expect(picker(flow)?.error?.contains("gone") == true)
        #expect(flow.selection.current == nil)
    }

    @Test func pastesGoToTheSearchOrTheKey() async {
        let flow = await loadedFlow()
        flow.paste("ignored")
        flow.openPicker()
        flow.paste("kimi")
        #expect(picker(flow)?.query == "kimi")
        flow.openConnect()
        flow.paste("not a key yet")
        #expect(setup(flow)?.key.isEmpty == true)
        setup(flow)?.highlight(2)
        #expect(flow.handle(KeyPress(key: .return)))
        flow.paste("sk-or-v1-1234")
        #expect(setup(flow)?.key == "sk-or-v1-1234")
    }

    @Test func modelCommandsSwitchOrOpenThePicker() async {
        let flow = await loadedFlow()
        await flow.run(.switchTo("go/kimi-k3"))
        #expect(flow.selection.current?.entry == Models.kimi)
        #expect(!flow.isOpen)
        await flow.run(.switchTo("codex/gpt-6"))
        #expect(picker(flow)?.query == "codex/gpt-6")
        flow.close()
        await flow.run(.openPicker)
        #expect(picker(flow)?.query.isEmpty == true)
    }

    @Test func theWorkspaceGivesOverlaysEveryKey() async throws {
        let flow = await loadedFlow()
        #expect(flow.handleWorkspaceKey(KeyPress(key: "x")) == nil)
        flow.openPicker()
        #expect(flow.handleWorkspaceKey(KeyPress(key: "x")) == true)
        #expect(picker(flow)?.query == "x")
        #expect(flow.handleWorkspaceKey(KeyPress(key: .tab)) == true)
        #expect(flow.handleWorkspaceKey(KeyPress(key: "c", modifiers: .control)) == true)
        #expect(!flow.isOpen)

        try await flow.selection.select(Models.codex, effort: nil)
        #expect(flow.handleWorkspaceKey(KeyPress(key: "x")) == true)
        #expect(flow.selection.isChatGPTWelcomeDue)
        #expect(flow.handleWorkspaceKey(KeyPress(key: .return)) == true)
        #expect(!flow.selection.isChatGPTWelcomeDue)
        #expect(flow.handleWorkspaceKey(KeyPress(key: .return)) == nil)
    }

    @Test func onboardingStartsWhereItCanAndQuitsOnCtrlC() async {
        let quits = SignIns()
        let connected = await loadedFlow(isOnboarding: true)
        #expect(!connected.handleOnboardingKey(KeyPress(key: "x")) { quits.providers.append(.codex) })
        #expect(connected.handleOnboardingKey(KeyPress(key: .return)) { quits.providers.append(.codex) })
        #expect(picker(connected) != nil)
        #expect(connected.handleOnboardingKey(KeyPress(key: "k")) { quits.providers.append(.codex) })
        #expect(picker(connected)?.query == "k")
        #expect(!connected.handleOnboardingKey(KeyPress(key: .return, phase: .up)) { quits.providers.append(.codex) })
        #expect(
            connected.handleOnboardingKey(KeyPress(key: "c", modifiers: .control)) { quits.providers.append(.codex) })
        #expect(quits.providers == [.codex])

        let selection = makeSelection(connected: false)
        await selection.load()
        let fresh = ModelFlow(selection: selection, isOnboarding: true)
        fresh.start()
        #expect(setup(fresh) != nil)
    }

    @Test(arguments: [
        ("/model", ModelCommand.openPicker),
        ("  /model  ", .openPicker),
        ("/model codex/gpt-6.1-sol", .switchTo("codex/gpt-6.1-sol")),
        ("/model   go/kimi-k3 ", .switchTo("go/kimi-k3")),
    ])
    func readsModelCommands(line: String, expected: ModelCommand) {
        #expect(ModelCommand(line) == expected)
    }

    @Test func otherLinesAreNotModelCommands() {
        #expect(ModelCommand("/models") == nil)
        #expect(ModelCommand("use /model") == nil)
        #expect(ModelCommand("/clear") == nil)
    }
}
