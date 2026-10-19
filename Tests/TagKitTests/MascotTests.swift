import Testing

@testable import Stipple
@testable import TagKit

@MainActor
struct MascotTests {
    private func workspace(height: Int, configure: (ChatSession) -> Void = { _ in }) -> String {
        let session = ChatSession()
        configure(session)
        let agent = Terminal([]).agent(model: ScriptedModel([]))
        let view = ChatView(session: session, agent: agent, copy: { _ in })
            .frame(height: height)
            .environment(\.terminalSize, Size(width: 100, height: height))
        return plainText(view, width: 100)
    }

    @Test func anEmptyConversationShowsTheCat() {
        let screen = workspace(height: 30)
        #expect(screen.contains("Tag Agent"))
        #expect(screen.contains("ask anything below"))
        #expect(screen.contains("▀"))
        let short = workspace(height: Welcome.catMinimumHeight - 1)
        #expect(short.contains("Tag Agent"))
        #expect(!short.contains("▀"))
        #expect(!workspace(height: 30) { $0.handle(.reply("hi")) }.contains("Tag Agent"))
    }

    @Test func theCatIsHalfBlocksTwoPixelsToACell() {
        #expect(Set(Mascot.sprite.map(\.count)).count == 1)
        #expect(Set(Mascot.sprite.joined()).subtracting(".").isSubset(of: Set(Mascot.palette.keys)))
        let lines = Mascot.lines.map { plainText($0) }
        #expect(lines.count == (Mascot.sprite.count + 1) / 2)
        // The fez's top row is the upper half of the first line; the ears start below it.
        #expect(lines[0] == "  ▄   ▀▀▀▀▀▀   ▄")
        let rendered = Stipple.renderToString(Mascot.lines[0])
        #expect(rendered.contains("38;2;216;64;63;48;2;216;64;63m▀▀▀"))
        #expect(rendered.contains("48;2;227;179;65m"))
    }
}
