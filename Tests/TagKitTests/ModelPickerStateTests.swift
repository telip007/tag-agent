import ModelKit
import Testing

@testable import Stipple
@testable import TagKit

@MainActor
struct ModelPickerStateTests {
    private func picker(
        query: String = "",
        catalogue: Catalogue? = Models.catalogue,
        current: ModelRef? = Models.kimi.ref,
        recent: [ModelRef] = [Models.kimi.ref],
        remembered: [ModelRef: String] = [:],
    ) -> ModelPickerState {
        ModelPickerState(query: query, catalogue: catalogue, current: current, recent: recent) { entry in
            remembered[entry.ref] ?? ModelSelection.defaultEffort(of: entry.reasoningEfforts)
        }
    }

    @Test func startsOnTheCurrentModel() {
        let state = picker(current: Models.gptRouter.ref)
        #expect(state.highlightedEntry == Models.gptRouter)
        #expect(!state.isLoading)
        #expect(picker(current: nil).highlightedEntry == Models.kimi)
    }

    @Test func aSearchStartsOnItsFirstMatch() {
        let state = picker(query: "flash")
        #expect(state.highlightedEntry == Models.deepseek)
        state.setQuery("mini")
        #expect(state.highlightedEntry == Models.codexMini)
        state.setQuery("nothing like this")
        #expect(state.highlighted == nil && state.highlightedEntry == nil)
    }

    @Test func movingSkipsTitlesAndStopsAtTheEnds() {
        let state = picker(recent: [])
        #expect(state.highlightedEntry == Models.kimi)
        state.move(by: -1)
        #expect(state.highlightedEntry == Models.codexMini)
        state.move(by: -10)
        #expect(state.highlightedEntry == Models.codex)
        state.move(by: 1)
        state.move(by: 1)
        #expect(state.highlightedEntry == Models.kimi)
        state.move(by: 99)
        #expect(state.highlightedEntry == Models.deepseek)
        state.highlight(0)
        #expect(state.highlightedEntry == Models.deepseek)
    }

    @Test func theWindowFollowsTheHighlight() {
        let state = picker(current: Models.codex.ref, recent: [])
        state.rowLimit = 3
        state.highlight(1)
        #expect(state.window(limit: 3) == 0..<3)
        state.move(by: 99)
        let last = state.rows.count - 1
        #expect(state.highlighted == last)
        #expect(state.window(limit: 3) == (last - 2)..<(last + 1))
        state.move(by: -99)
        // The first model brings its provider's title into view.
        #expect(state.window(limit: 3).lowerBound == 0)
    }

    @Test func effortsStartRememberedOrInTheMiddleAndWrap() {
        let state = picker(current: Models.codexMini.ref, remembered: [Models.codex.ref: "high"])
        #expect(state.effort(for: Models.codexMini) == "high")
        state.cycleEffort(by: 1)
        #expect(state.effort(for: Models.codexMini) == "xhigh")
        state.cycleEffort(by: 1)
        #expect(state.effort(for: Models.codexMini) == "minimal")
        state.cycleEffort(by: -1)
        #expect(state.effort(for: Models.codexMini) == "xhigh")
        #expect(state.effort(for: Models.codex) == "high")
        #expect(state.effort(for: Models.kimi) == nil)
    }

    @Test func modelsWithoutEffortsIgnoreTheArrows() {
        let state = picker(current: Models.kimi.ref)
        state.cycleEffort(by: 1)
        #expect(state.efforts.isEmpty)
    }

    @Test func typingEditsTheSearch() {
        let state = picker()
        state.type("go")
        state.type(" ki\n")
        #expect(state.query == "go ki")
        state.deleteBackward()
        #expect(state.query == "go k")
        state.deleteWord()
        #expect(state.query == "go ")
        state.deleteWord()
        #expect(state.query.isEmpty)
    }

    @Test func loadingKeepsTheHighlightedModel() {
        let state = picker(catalogue: nil, current: Models.deepseek.ref)
        #expect(state.isLoading && state.rows.isEmpty)
        state.update(catalogue: Models.catalogue)
        #expect(!state.isLoading)
        #expect(state.highlightedEntry == Models.deepseek)
        state.move(by: -1)
        state.update(catalogue: Models.catalogue)
        #expect(state.highlightedEntry == Models.gptRouter)
        #expect(!state.hasNoModels)
    }

    @Test func aNewSearchClearsTheLastError() {
        let state = picker()
        state.error = "nope"
        state.type("k")
        #expect(state.error == nil)
    }

    @Test func keysBecomeActions() {
        let state = picker(current: Models.codex.ref)
        #expect(state.handle(KeyPress(key: .return)).action == .use(Models.codex, effort: "medium"))
        #expect(state.handle(KeyPress(key: .rightArrow)).handled)
        #expect(state.handle(KeyPress(key: .return)).action == .use(Models.codex, effort: "high"))
        #expect(state.handle(KeyPress(key: .escape)).action == .close)
        #expect(state.handle(KeyPress(key: "a", modifiers: .control)).action == .connect)
        #expect(state.handle(KeyPress(key: "k")) == (true, nil))
        #expect(state.query == "k")
        #expect(state.handle(KeyPress(key: "u", modifiers: .control)).handled)
        #expect(state.query.isEmpty)
        #expect(state.handle(KeyPress(key: .tab)) == (false, nil))
        state.setQuery("zzzz")
        #expect(state.handle(KeyPress(key: .return)) == (true, nil))
    }

    @Test func pagesMoveByTheWindow() {
        let state = picker(current: Models.codex.ref, recent: [])
        state.rowLimit = 2
        _ = state.handle(KeyPress(key: .pageDown))
        #expect(state.highlightedEntry == Models.kimi)
        _ = state.handle(KeyPress(key: .pageUp))
        #expect(state.highlightedEntry == Models.codex)
    }

    @Test(arguments: [
        (KeyPress(key: .upArrow), PickerKey.move(-1)),
        (KeyPress(key: "p", modifiers: .control), .move(-1)),
        (KeyPress(key: .downArrow), .move(1)),
        (KeyPress(key: "n", modifiers: .control), .move(1)),
        (KeyPress(key: .pageUp), .move(.min)),
        (KeyPress(key: .pageDown), .move(.max)),
        (KeyPress(key: .leftArrow), .effort(-1)),
        (KeyPress(key: .rightArrow), .effort(1)),
        (KeyPress(key: .return), .use),
        (KeyPress(key: .escape), .close),
        (KeyPress(key: "a", modifiers: .control), .connect),
        (KeyPress(key: "u", modifiers: .control), .clear),
        (KeyPress(key: "w", modifiers: .control), .deleteWord),
        (KeyPress(key: .backspace, modifiers: .option), .deleteWord),
        (KeyPress(key: .backspace), .deleteBackward),
        (KeyPress(key: "K", modifiers: .shift), .type("K")),
        (KeyPress(key: "s", characters: "sk-paste"), .type("sk-paste")),
    ])
    func mapsPickerKeys(press: KeyPress, expected: PickerKey) {
        #expect(PickerKey(press) == expected)
    }

    @Test func ignoresReleasesAndOtherKeys() {
        #expect(PickerKey(KeyPress(key: .return, phase: .up)) == nil)
        #expect(PickerKey(KeyPress(key: .tab)) == nil)
        #expect(PickerKey(KeyPress(key: "x", modifiers: .control)) == nil)
    }
}
