import Foundation
import ModelKit
import Stipple

/// `/model` at the prompt: alone it opens the picker; with a
/// `provider/model` it switches straight away.
enum ModelCommand: Equatable {
    /// `/model`.
    case openPicker
    /// `/model codex/gpt-6.1-sol`: switch, or search for the text.
    case switchTo(String)

    /// Reads the command from a submitted line, or `nil` when it's another line.
    init?(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed == "/model" || trimmed.hasPrefix("/model ") else {
            return nil
        }
        let rest = trimmed.dropFirst("/model".count).trimmingCharacters(in: .whitespaces)
        self = rest.isEmpty ? .openPicker : .switchTo(rest)
    }
}

/// The model lines of the session panel: its name, its effort, and
/// "Using ChatGPT plan" for models on the user's ChatGPT plan, as OpenAI
/// asks apps to say near the model.
struct ModelSummary: View {
    let selection: ModelSelection
    /// The name from the latest status line, until a model is chosen.
    let fallback: String?

    var body: some View {
        VStack(alignment: .leading) {
            if let current = selection.current {
                Text(current.entry.name).bold().lineLimit(1)
                Text(Self.detail(current)).dim().lineLimit(1)
                if current.entry.ref.provider == .codex {
                    Text("Using ChatGPT plan").foregroundStyle(Theme.tile)
                }
            } else if let fallback {
                Text(fallback).bold().lineLimit(1)
            }
        }
    }

    /// `opencode go · medium`: the provider, and the effort when there is one.
    static func detail(_ model: ActiveModel) -> String {
        ([PickerList.label(model.entry.ref.provider)] + [model.effort].compactMap(\.self)).joined(separator: " · ")
    }
}

/// The one-time notice the first time a model on the ChatGPT plan is used.
struct ChatGPTWelcomeNotice: View {
    let dismiss: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading) {
            Text("You're using your ChatGPT plan").bold()
            Text(" ")
            Text("Replies from ChatGPT (Codex) models count toward your plan's usage limits, not API credits.")
            Text(" ")
            KeyHints(keys: [Footer.Key(key: "↵", label: "Got it", action: dismiss)])
        }
        .modal(title: "ChatGPT plan", width: 56)
    }
}

/// A failed model call in the transcript: what went wrong, and what to do,
/// such as where to manage usage.
struct FailureView: View {
    let message: String
    let recovery: String?

    var body: some View {
        VStack(alignment: .leading) {
            Text("✗ ").foregroundStyle(Theme.removed) + Text(message)
            if let recovery {
                Text(recovery).dim().padding(.leading, 2)
            }
        }
    }
}
