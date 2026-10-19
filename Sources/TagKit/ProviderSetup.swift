import Foundation
import ModelKit
import Stipple

/// "Connect a provider": each provider with its status, and connecting one,
/// by pasting an API key or by signing in with the browser.
///
/// ```text
/// ╭─ connect a provider ─────────────────────────────╮
/// │ › ChatGPT (Codex)      Continue with ChatGPT     │
/// │   OpenCode Go          paste an API key          │
/// │   OpenRouter           ✓ connected               │
/// │                                                  │
/// │ ✓ OpenRouter connected.                          │
/// │ ↵ connect · esc close                            │
/// ╰──────────────────────────────────────────────────╯
/// ```
///
/// Shown over the workspace from the model picker (Ctrl-A) and as a step of
/// the onboarding, where it ends with "Continue". Keys reach it through its
/// owner, which calls ``ProviderSetupState/handle(_:)``.
struct ProviderSetup: View {
    static let nameWidth = 20

    let state: ProviderSetupState
    let width: Int
    let perform: @MainActor (SetupAction) -> Void

    var body: some View {
        VStack(alignment: .leading) {
            switch state.phase {
            case .list:
                list
            case .key(let provider):
                keyEntry(provider)
            case .signingIn(let provider):
                signingIn(provider)
            }
            Text(" ")
            status
            hints
        }
        .modal(title: title, width: width)
    }

    private var title: String {
        switch state.phase {
        case .list: "connect a provider"
        case .key(let provider), .signingIn(let provider): "connect \(provider.displayName)"
        }
    }

    private var list: some View {
        VStack(alignment: .leading) {
            ForEach(Array(state.items.enumerated()), id: \.offset) { index, item in
                let isHighlighted = index == state.highlighted
                itemLine(item, isHighlighted: isHighlighted)
                    .frame(width: width - 4, alignment: .leading)
                    .background(isHighlighted ? Theme.selection : Theme.overlay)
                    .onTapGesture { [state, perform] in
                        state.highlight(index)
                        if let action = state.activate() {
                            perform(action)
                        }
                    }
            }
        }
    }

    @ViewBuilder private func itemLine(_ item: SetupItem, isHighlighted: Bool) -> some View {
        let color = isHighlighted ? Theme.accent : nil
        switch item {
        case .provider(let provider):
            HStack {
                Text(isHighlighted ? "› " : "  ").foregroundStyle(Theme.accent)
                Text(provider.displayName).foregroundStyle(color).bold(isHighlighted)
                    .frame(width: Self.nameWidth, alignment: .leading)
                providerStatus(provider)
            }
        case .proceed:
            HStack {
                Text(isHighlighted ? "› " : "  ").foregroundStyle(Theme.accent)
                Text("Continue →").foregroundStyle(color).bold(isHighlighted).dim(!state.canProceed)
            }
            .padding(.top, 1)
        }
    }

    /// `✓ connected`, or how it connects: "Continue with ChatGPT" is
    /// OpenAI's wording for its sign-in.
    private func providerStatus(_ provider: ProviderID) -> Text {
        if let failure = state.selection.catalogue?.failures[provider] {
            return Text("✗ ").foregroundStyle(Theme.removed) + Text(failure).dim()
        }
        if state.selection.connected.contains(provider) {
            return Text("✓ ").foregroundStyle(Theme.added) + Text("connected").dim()
        }
        switch state.method(of: provider) {
        case .browser: return Text(provider == .codex ? "Continue with ChatGPT" : "sign in with the browser").dim()
        case .apiKey, nil: return Text("paste an API key").dim()
        }
    }

    @ViewBuilder private func keyEntry(_ provider: ProviderID) -> some View {
        VStack(alignment: .leading) {
            if case .apiKey(let variable, let url) = state.method(of: provider) {
                Text("Get an API key at ") + Text(url.absoluteString).foregroundStyle(Theme.tile)
                Text("and paste it here, or set \(variable).").dim()
            }
            Text(" ")
            SearchLine(query: ProviderSetupState.masked(state.key), placeholder: "paste your key")
        }
    }

    private func signingIn(_ provider: ProviderID) -> some View {
        VStack(alignment: .leading) {
            Text(provider == .codex ? "Continue with ChatGPT" : "Sign in with \(provider.displayName)").bold()
            Text(" ")
            TimelineView(.periodic(every: .milliseconds(80))) { context in
                Text("\(Footer.frames[context.frame % Footer.frames.count]) ").foregroundStyle(Theme.accent)
                    + Text("Finish signing in in your browser…")
            }
        }
    }

    /// The last error, else the last success, else a blank line.
    private var status: Text {
        if let error = state.error {
            return Text("✗ ").foregroundStyle(Theme.removed) + Text(error)
        }
        if let notice = state.notice {
            return Text("✓ ").foregroundStyle(Theme.added) + Text(notice)
        }
        return Text(" ")
    }

    private var hints: KeyHints {
        let back = Footer.Key(key: "esc", label: "back") { [state] in state.cancel() }
        switch state.phase {
        case .list:
            let close = state.offersProceed ? "back" : "close"
            return KeyHints(keys: [
                Footer.Key(key: "↵", label: "connect") { [state, perform] in
                    if let action = state.activate() {
                        perform(action)
                    }
                },
                Footer.Key(key: "esc", label: close) { [perform] in perform(.close) },
            ])
        case .key:
            return KeyHints(keys: [
                Footer.Key(key: "↵", label: "save") { [state] in Task { await state.saveKey() } }, back,
            ])
        case .signingIn:
            return KeyHints(keys: [Footer.Key(key: "esc", label: "cancel") { [state] in state.cancel() }])
        }
    }
}
