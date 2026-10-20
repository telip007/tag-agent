import Foundation
import ModelKit
import SessionKit
import Stipple

/// Recognizable conversation titles and a bounded preview, before any switch.
struct SessionPicker: View {
    let state: SessionFlow
    let width: Int
    let height: Int

    private var wide: Bool { width >= 100 }
    private var contentHeight: Int { max(8, height - 10) }
    private var visibleRows: Int { max(1, min(state.rowLimit, (contentHeight - (wide ? 0 : 8)) / 3)) }

    var body: some View {
        if let excerpts = state.referencePreview {
            SessionReferencePreview(
                excerpts: excerpts, width: width, height: height, error: state.error,
                position: Binding(get: { state.referenceScroll }, set: { state.referenceScroll = $0 })
            ) {
                state.attach()
            } cancel: {
                state.dismissReference()
            }
        } else {
            navigator
        }
    }

    private var navigator: some View {
        VStack(alignment: .leading) {
            SearchLine(
                query: state.renameText ?? state.query,
                placeholder: state.renameText == nil ? "search titles and conversations" : "rename session",
                isLoading: state.isLoading
            )
            .frame(height: 1, alignment: .leading).clipped()
            scopeLine
            Text(" ")
            content
                .frame(height: contentHeight, alignment: .topLeading).clipped()
            Text(" ")
            Text(state.error ?? action).foregroundStyle(state.error == nil ? Theme.accent : Theme.removed)
                .lineLimit(1)
            primaryHints
            secondaryHints
        }
        .modal(title: state.purpose == .reference ? "reference a session" : "sessions", width: width)
    }

    private var scopeLine: some View {
        HStack {
            Text(state.allWorkspaces ? "all workspaces" : "this workspace").dim()
            Spacer(minLength: 1)
            Text(
                "\(state.rows.count)\(state.hasMore ? "+" : "") \(state.rows.count == 1 && !state.hasMore ? "session" : "sessions")"
            ).dim()
        }.lineLimit(1)
    }

    @ViewBuilder private var content: some View {
        let inner = max(1, width - 4)
        if wide {
            let listWidth = (inner - 3) / 2
            HStack(alignment: .top) {
                list(width: listWidth).frame(width: listWidth, alignment: .topLeading)
                Text(Array(repeating: "│", count: contentHeight).joined(separator: "\n")).foregroundStyle(Theme.rule)
                    .frame(width: 3)
                preview(height: contentHeight).frame(width: inner - listWidth - 3, alignment: .topLeading)
            }
        } else {
            VStack(alignment: .leading) {
                list(width: inner).frame(height: max(3, visibleRows * 3), alignment: .topLeading)
                Text("─ preview ─").foregroundStyle(Theme.rule)
                preview(height: max(4, contentHeight - visibleRows * 3 - 1))
            }
        }
    }

    private func list(width: Int) -> some View {
        VStack(alignment: .leading) {
            if state.rows.isEmpty {
                Text(
                    state.isLoading
                        ? "Loading sessions…"
                        : state.query.isEmpty
                            ? "No saved sessions. ^n creates one."
                            : "No matches. Try fewer words or Tab for all workspaces."
                )
                .dim().lineLimit(3)
            }
            ForEach(Array(state.window(limit: visibleRows)), id: \.self) { index in
                let summary = state.rows[index]
                SessionPickerRow(
                    summary: summary, current: summary.id == state.controller.active?.id,
                    highlighted: summary.id == state.selectedID, allWorkspaces: state.allWorkspaces
                )
                .frame(width: width, height: 3, alignment: .topLeading)
                .onTapGesture { state.highlight(summary.id) }
                .onTapGesture(count: 2) {
                    state.highlight(summary.id)
                    state.requestActivation(summary.id)
                }
            }
        }
    }

    private func preview(height: Int) -> some View {
        VStack(alignment: .leading) {
            if let selected = state.selected {
                Text(SessionPresentation.clean(selected.context.model.description)).dim().lineLimit(1)
                Text(SessionPresentation.clean(selected.workspace)).dim().lineLimit(1)
                Text(
                    "\(selected.id.uuidString.prefix(8).lowercased()) · \(SessionPresentation.age(selected.updatedAt))"
                ).dim().lineLimit(1)
                Text(state.isPreviewLoading ? "Loading conversation…" : SessionPresentation.excerpts(state.preview))
                    .lineLimit(max(1, height - 3))
            } else {
                Text("Choose a conversation to preview it.").dim().lineLimit(2)
            }
        }.frame(height: height, alignment: .topLeading).clipped()
    }

    private var action: String {
        if state.renameText != nil { return "Rename this session · Enter saves, Esc cancels" }
        if state.controller.isBusy { return "Current turn is active · preview now, switch when ready" }
        if state.purpose == .reference { return "Preview excerpts before attaching · no model request" }
        if state.selected?.workspace != state.controller.workspace { return "inspect · open its workspace to continue" }
        return "continue · keep the current draft saved"
    }

    private var primaryHints: some View {
        let navigation = state.renameText == nil ? [Footer.Key(key: "↑↓", label: "move") { state.move(by: 1) }] : []
        return KeyHints(
            keys: navigation + [
                Footer.Key(
                    key: "↵", label: state.renameText != nil ? "save" : state.purpose == .reference ? "preview" : "open"
                ) {
                    state.requestActivation()
                },
                Footer.Key(key: "esc", label: "back") {
                    if state.renameText != nil { state.cancelRename() } else { state.close() }
                },
            ]
        ).lineLimit(1)
    }

    @ViewBuilder private var secondaryHints: some View {
        if state.renameText != nil {
            KeyHints(keys: [
                Footer.Key(key: "^u", label: "clear") { state.renameText = "" },
                Footer.Key(key: "^w", label: "word") { _ = state.handle(KeyPress(key: "w", modifiers: .control)) },
            ]).lineLimit(1)
        } else {
            KeyHints(keys: [
                Footer.Key(key: "^n", label: "new") { Task { await state.create() } },
                Footer.Key(key: "^r", label: "rename") { state.beginRename() },
                Footer.Key(key: "tab", label: "scope") { state.toggleScope() },
                Footer.Key(key: "^l", label: "ref") {
                    state.requestReference()
                },
            ]).lineLimit(1)
        }
    }
}

private struct SessionPickerRow: View {
    let summary: SessionSummary
    let current: Bool
    let highlighted: Bool
    let allWorkspaces: Bool

    var body: some View {
        VStack(alignment: .leading) {
            Text((current ? "● " : "  ") + SessionPresentation.clean(summary.title))
                .bold(highlighted).foregroundStyle(highlighted ? Theme.accent : nil).lineLimit(1)
            Text("  " + SessionPresentation.clean(summary.preview ?? summary.context.model.description)).dim()
                .lineLimit(1)
            Text(
                "  " + (current ? "current · " : "")
                    + (allWorkspaces
                        ? SessionPresentation.clean(URL(filePath: summary.workspace).lastPathComponent) + " · " : "")
                    + SessionPresentation.age(summary.updatedAt)
            ).dim().lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading)
            .background(highlighted ? Theme.selection : Theme.overlay)
    }
}
