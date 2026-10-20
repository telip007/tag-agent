import Testing

@testable import TagKit

struct SessionCommandTests {
    @Test func localSessionCommandsNeverBecomeOrdinaryPrompts() {
        #expect(SessionCommand(" /sessions ") == .browse)
        #expect(SessionCommand("/clear") == .new)
        #expect(SessionCommand("/session 123") == .resume("123"))
        #expect(SessionCommand("/rename parser work") == .rename("parser work"))
        #expect(SessionCommand("/reference") == .reference(nil, ""))
        #expect(SessionCommand("/reference 123 parser \"OR\"") == .reference("123", "parser \"OR\""))
        #expect(SessionCommand("/pending") == .pending)
        #expect(SessionCommand("/retry") == .retry)
        #expect(SessionCommand("/session") == .invalid("Usage: /session <id>"))
        #expect(SessionCommand("/new unexpected") == .invalid("Usage: /new"))
        #expect(SessionCommand("please /new here") == nil)
        #expect(SessionCommand("/sessions-extra") == nil)
    }
}
