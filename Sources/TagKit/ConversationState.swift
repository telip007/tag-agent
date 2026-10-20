import Foundation
import ModelKit
import SessionKit

/// What the agent keeps about the conversation between model calls.
struct ConversationState {
    /// The model the conversation was last sent to.
    private(set) var model: ModelRef
    /// Its name and context window, for the status line.
    private(set) var description: ModelDescription
    /// Everything the model is told, the system prompt first.
    var conversation: [Message]
    /// Dates user messages when the day changed.
    var dater = UserMessageDater()
    /// Tokens the context held after the latest reply.
    private(set) var contextTokens = 0
    /// Usage from the latest reply; absent metrics never inherit an old hit.
    private(set) var latestUsage: Usage?
    /// What the conversation has cost so far, in US dollars.
    private(set) var cost = 0.0
    /// The conversation's id for providers that route or cache by session.
    private(set) var sessionID = UUID().uuidString
    private var projectedPrefix: [Message]?
    private var projectedCount = 0
    private let prompt: (ModelDescription) -> String

    init(active: ActiveModel, prompt: @escaping (ModelDescription) -> String) {
        model = active.entry.ref
        description = active.description
        self.prompt = prompt
        // Rendered once per model: changing it would invalidate the cache.
        conversation = [.system(prompt(active.description))]
    }

    init(
        active: ActiveModel, prompt: @escaping (ModelDescription) -> String, snapshot: SessionSnapshot,
        projectionEnabled: Bool = true
    ) {
        self.init(active: active, prompt: prompt)
        sessionID = snapshot.summary.providerSessionID
        dater = UserMessageDater(lastDate: snapshot.summary.lastDate)
        contextTokens = snapshot.summary.contextTokens
        cost = snapshot.summary.cost
        let current = SessionContext(prompt: prompt(active.description), model: active.entry.ref, effort: active.effort)
        latestUsage = current == snapshot.summary.context ? snapshot.summary.latestUsage : nil
        conversation += snapshot.entries.compactMap { ContextRequestProjection.message($0.event) }
        if projectionEnabled { projectedPrefix = ContextRequestProjection.prefix(snapshot, system: conversation[0]) }
        projectedCount = conversation.count
    }

    /// A derived request view; the canonical in-memory conversation remains available.
    var requestConversation: [Message] {
        guard var prefix = projectedPrefix else { return conversation }
        prefix[0] = conversation[0]
        return prefix + conversation.dropFirst(projectedCount)
    }

    mutating func clearLatestUsage() {
        latestUsage = nil
    }

    /// Starts over: the system prompt stays; everything the model was told
    /// goes, so the prompt cache prefix does too.
    mutating func reset() {
        conversation = [.system(prompt(description))]
        projectedPrefix = nil
        projectedCount = 0
        dater = UserMessageDater()
        contextTokens = 0
        clearLatestUsage()
        cost = 0
        sessionID = UUID().uuidString
    }

    /// Switches to `active` when it is another model: the system prompt
    /// names the new model and the rest of the conversation carries over.
    mutating func follow(_ active: ActiveModel) {
        guard active.entry.ref != model else {
            return
        }
        model = active.entry.ref
        description = active.description
        clearLatestUsage()
        conversation[0] = .system(prompt(description))
    }

    /// Adds the reply and its usage.
    mutating func record(_ reply: ModelReply) {
        conversation.append(.assistant(reply.message))
        latestUsage = reply.usage
        if let usage = reply.usage {
            contextTokens = usage.totalTokens
            cost += usage.cost ?? 0
        }
    }
}
