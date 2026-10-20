import Foundation
import SessionKit
import Stipple

/// Historical evidence remains inspectable after sending and after reopening.
struct ReferenceTranscript: View {
    let excerpts: [SessionReference]
    let isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading) {
            Text("\(isExpanded ? "▾" : "▸") \(excerpts.count) session \(excerpts.count == 1 ? "excerpt" : "excerpts")")
                .foregroundStyle(Theme.tile)
            if isExpanded {
                ForEach(Array(excerpts.enumerated()), id: \.offset) { _, excerpt in
                    VStack(alignment: .leading) {
                        Text(SessionPresentation.clean(excerpt.source.title)).bold().lineLimit(1)
                        Text(
                            "\(excerpt.source.sessionID.uuidString.prefix(8).lowercased()) · entry \(excerpt.source.sequence) · \(excerpt.source.role)"
                        )
                        .dim().lineLimit(1)
                        Text(SessionPresentation.clean(excerpt.text))
                    }.padding(.leading, 2).padding(.top, 1)
                }
            }
        }
    }
}
