import Stipple

/// The conversation in a scroll view. A short conversation starts at the top;
/// once it fills the pane, the view follows the newest block until the user
/// scrolls up (wheel, Page Up), and pins again back at the bottom. A click on
/// a block expands or collapses it.
struct TranscriptPane: View, Equatable {
    let session: ChatSession
    let selected: Int?
    @Binding var position: ScrollPosition
    var loadEarlier: (@MainActor () -> Void)?
    @State private var hover = HoverState()

    /// The same session and selection: what `ChatView` changes on a resize or
    /// a key leaves the pane, and its rows, alone. The position is always the
    /// workspace's own scroll state, so it isn't compared.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.session === rhs.session && lhs.selected == rhs.selected
    }

    var body: some View {
        if session.blocks.isEmpty {
            Welcome()
        } else {
            conversation
        }
    }

    private var conversation: some View {
        ScrollView {
            // Lazy: a resize lays out the rows in view at once and the long
            // history above over the next frames.
            LazyVStack(alignment: .leading) {
                if session.hasEarlier {
                    Text("↑ earlier messages").foregroundStyle(Theme.accent)
                        .onTapGesture {
                            if let loadEarlier { loadEarlier() } else { session.loadEarlier() }
                        }
                }
                // `ForEach` gives each row its block's id, for `scrollTo(id:)`.
                ForEach(session.blocks) { block in
                    BlockRow(
                        block: block,
                        session: session,
                        hover: hover,
                        isExpanded: session.expanded.contains(block.id),
                        isSelected: block.id == selected,
                        isHovered: block.id == hover.block,
                    )
                }
            }
            .padding(.bottom, 1)
        }
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .scrollPosition($position)
        .scrollOnPageKeys()
    }
}
