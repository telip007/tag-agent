import Foundation
import ModelKit
import Observation
import Stipple

/// A line of "connect a provider": a provider, or, during onboarding, going on.
enum SetupItem: Hashable {
    case provider(ProviderID)
    case proceed
}

/// What "connect a provider" asks its owner to do.
enum SetupAction: Equatable {
    /// Close, or go back to where it was opened from.
    case close
    /// Onboarding: a provider is connected, go on to picking a model.
    case proceed
}

/// The state of "connect a provider": the list of providers, pasting an
/// API key, or waiting for a browser sign-in. The view only draws it.
@MainActor
@Observable
final class ProviderSetupState {
    /// What the box shows.
    enum Phase: Equatable {
        /// The providers, with their status.
        case list
        /// Pasting an API key for the provider.
        case key(ProviderID)
        /// Waiting for the provider's browser sign-in.
        case signingIn(ProviderID)
    }

    let selection: ModelSelection
    /// Whether the list ends with "Continue", for onboarding.
    let offersProceed: Bool
    private(set) var phase = Phase.list
    /// The highlighted line of ``items``.
    private(set) var highlighted = 0
    /// The key being pasted.
    private(set) var key = ""
    /// What went wrong last, shown until the next attempt.
    private(set) var error: String?
    /// What went right last: `OpenRouter connected.`
    private(set) var notice: String?
    @ObservationIgnored private var signInTask: Task<Void, Never>?

    init(selection: ModelSelection, offersProceed: Bool = false) {
        self.selection = selection
        self.offersProceed = offersProceed
    }

    /// The providers in display order, then "Continue" during onboarding.
    var items: [SetupItem] {
        selection.registry.providers.map { .provider($0.id) } + (offersProceed ? [.proceed] : [])
    }

    /// Whether going on is possible: a provider is connected.
    var canProceed: Bool {
        !selection.connected.isEmpty
    }

    /// How `provider` connects.
    func method(of provider: ProviderID) -> ConnectMethod? {
        selection.registry.provider(provider)?.connectMethod
    }

    /// Highlights line `index`.
    func highlight(_ index: Int) {
        highlighted = min(max(index, 0), items.count - 1)
    }

    /// Starts connecting the highlighted provider, or goes on.
    func activate() -> SetupAction? {
        guard items.indices.contains(highlighted) else {
            return nil
        }
        switch items[highlighted] {
        case .proceed:
            guard canProceed else {
                error = "Connect a provider first."
                return nil
            }
            return .proceed
        case .provider(let provider):
            error = nil
            notice = nil
            if case .browser = method(of: provider) {
                startSignIn(provider)
            } else {
                key = ""
                phase = .key(provider)
            }
            return nil
        }
    }

    /// Adds pasted or typed text to the key.
    func type(_ text: String) {
        key += text
        error = nil
    }

    /// Removes the key's last character.
    func deleteBackward() {
        key = String(key.dropLast())
    }

    /// Checks the pasted key and stores it.
    func saveKey() async {
        guard case .key(let provider) = phase else {
            return
        }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if let problem = Self.problem(with: trimmed) {
            error = problem
            return
        }
        do {
            try await selection.saveAPIKey(trimmed, for: provider)
            finishConnecting(provider)
        } catch {
            self.error = "Couldn't save the key: \(error.localizedDescription)"
        }
    }

    /// Why `key` can't be an API key, or `nil` when it can.
    static func problem(with key: String) -> String? {
        if key.isEmpty {
            return "Paste a key first."
        }
        if key.contains(where: \.isWhitespace) {
            return "A key has no spaces. Check what you pasted."
        }
        return nil
    }

    /// Starts the browser sign-in in the background.
    func startSignIn(_ provider: ProviderID) {
        phase = .signingIn(provider)
        signInTask = Task { await signIn(provider) }
    }

    /// Signs in with the browser and waits for it to finish.
    func signIn(_ provider: ProviderID) async {
        phase = .signingIn(provider)
        do {
            try await selection.signIn(provider)
            finishConnecting(provider)
        } catch is CancellationError {
            phase = .list
        } catch {
            phase = .list
            self.error = error.localizedDescription
        }
        signInTask = nil
    }

    /// Stops waiting for the sign-in.
    func cancel() {
        signInTask?.cancel()
        signInTask = nil
        phase = .list
        key = ""
    }

    /// Back to the list, saying whether the provider works now.
    private func finishConnecting(_ provider: ProviderID) {
        phase = .list
        key = ""
        if let failure = selection.catalogue?.failures[provider] {
            error = failure
        } else {
            notice = "\(provider.displayName) connected."
            if offersProceed, let index = items.firstIndex(of: .proceed) {
                highlighted = index
            }
        }
    }

    /// `•••••••••abcd`: the last four characters of a key, the rest hidden.
    static func masked(_ key: String) -> String {
        let hidden = String(repeating: "•", count: min(max(key.count - 4, 0), 24))
        return key.count <= 4 ? String(repeating: "•", count: key.count) : hidden + key.suffix(4)
    }
}

extension ProviderSetupState {
    /// Acts on a key press for the current phase.
    ///
    /// - Returns: Whether the press was handled, and what the owner should do.
    func handle(_ press: KeyPress) -> (handled: Bool, action: SetupAction?) {
        guard press.phase != .up else {
            return (false, nil)
        }
        let modifiers = press.modifiers.subtracting([.capsLock, .numLock, .shift])
        switch phase {
        case .list:
            return handleList(press.key, modifiers: modifiers)
        case .key:
            switch (press.key, modifiers) {
            case (.escape, []): cancel()
            case (.return, []): Task { await saveKey() }
            case (.backspace, _): deleteBackward()
            case ("u", .control): key = ""
            default:
                guard let text = press.typedText else {
                    return (false, nil)
                }
                type(text)
            }
            return (true, nil)
        case .signingIn:
            guard press.key == .escape else {
                return (false, nil)
            }
            cancel()
            return (true, nil)
        }
    }

    private func handleList(_ key: KeyEquivalent, modifiers: EventModifiers) -> (handled: Bool, action: SetupAction?) {
        switch (key, modifiers) {
        case (.upArrow, []), ("k", []): highlight(highlighted - 1)
        case (.downArrow, []), ("j", []): highlight(highlighted + 1)
        case (.return, []): return (true, activate())
        case (.escape, []): return (true, .close)
        default: return (false, nil)
        }
        return (true, nil)
    }
}
