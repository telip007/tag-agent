import Foundation
import Stipple

/// What the command palette offers.
enum PaletteCommand: String, CaseIterable, Identifiable {
    case togglePanel = "Show or hide the session panel"
    case copyLastReply = "Copy the last reply"
    case browse = "Browse the conversation"
    case quit = "Quit"

    var id: Self { self }

    var key: String {
        switch self {
        case .togglePanel: "tab"
        case .copyLastReply: ""
        case .browse: "esc"
        case .quit: "^d"
        }
    }
}

/// A small box over the workspace listing the commands.
struct CommandPalette: View {
    @Binding var selection: PaletteCommand?
    let run: @MainActor (PaletteCommand) -> Void

    var body: some View {
        VStack(alignment: .leading) {
            Text("commands").foregroundStyle(Theme.accent)
            Text(" ")
            SelectionList(PaletteCommand.allCases, id: \.self, selection: $selection, onSubmit: run) { command in
                HStack {
                    Text(command.rawValue)
                    Spacer(minLength: 2)
                    Text(command.key).dim()
                }
                .onTapGesture { run(command) }
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 1)
        .frame(width: 48)
        .background(Color(red: 36, green: 39, blue: 52))
        .border(.rounded, color: Theme.accent)
    }
}

/// Copies text with the terminal's clipboard escape (OSC 52), which works
/// over SSH too. Terminals that don't support it ignore it.
public enum Clipboard {
    /// The escape that puts `text` on the clipboard.
    static func sequence(for text: String) -> String {
        "\u{1B}]52;c;\(Data(text.utf8).base64EncodedString())\u{07}"
    }

    /// Writes the clipboard escape to standard output.
    @MainActor
    public static func copy(_ text: String) {
        FileHandle.standardOutput.write(Data(sequence(for: text).utf8))
    }
}
