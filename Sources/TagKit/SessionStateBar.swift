import SessionKit
import Stipple

/// Execution state and unsent attachments stay visible without covering the editor.
struct SessionStateBar: View {
    let controller: SessionController
    let error: String?

    var body: some View {
        if let message = error ?? controller.pauseReason ?? controller.readOnlyReason {
            Text(SessionPresentation.clean(message)).foregroundStyle(Theme.removed).lineLimit(2)
        } else if controller.needsModel {
            Text("Saved model unavailable · /model chooses how to continue").foregroundStyle(Theme.accent).lineLimit(1)
        } else if !controller.draft.references.isEmpty {
            Text("\(controller.draft.references.count) session excerpts attached · /unreference removes them")
                .foregroundStyle(Theme.accent).lineLimit(1)
        } else if !controller.pendingForReview.isEmpty {
            Text("\(controller.pendingForReview.count) saved inputs await review · /pending opens the next one").dim()
                .lineLimit(1)
        }
    }
}
