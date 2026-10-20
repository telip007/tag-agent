import Stipple

/// Shared prompt hints keep keyboard and mouse actions identical.
@MainActor
enum WorkspaceHints {
    static func browsing(
        toggle: @escaping @MainActor () -> Void, copy: @escaping @MainActor () -> Void,
        back: @escaping @MainActor () -> Void
    ) -> Footer.Hint {
        .keys([
            Footer.Key(key: "↑↓", label: "move") {},
            Footer.Key(key: "⏎", label: "expand", action: toggle),
            Footer.Key(key: "c", label: "copy", action: copy),
            Footer.Key(key: "esc", label: "back", action: back),
        ])
    }

    static func prompt(
        durable: Bool,
        browse: @escaping @MainActor () -> Void,
        sessions: @escaping @MainActor () -> Void,
        palette: @escaping @MainActor () -> Void,
        togglePanel: @escaping @MainActor () -> Void
    ) -> Footer.Hint {
        let sessionKeys = durable ? [Footer.Key(key: "^o", label: "sessions", action: sessions)] : []
        return .keys(
            [Footer.Key(key: "esc", label: "browse", action: browse)] + sessionKeys + [
                Footer.Key(key: "^p", label: "commands", action: palette),
                Footer.Key(key: "tab", label: "panel", action: togglePanel),
            ])
    }
}
