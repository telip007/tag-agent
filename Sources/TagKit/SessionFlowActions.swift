import Foundation
import SessionKit
import Stipple

extension SessionFlow {
    func requestActivation(_ id: UUID? = nil) {
        guard let id = id ?? selectedID else { return }
        let request = generation
        Task {
            guard isOpen, request == generation else { return }
            await activate(id)
        }
    }

    func requestReference() {
        guard !isLoading, let id = selectedID else { return }
        let request = generation
        let query = query
        Task {
            guard isOpen, request == generation else { return }
            do { try await reference(id, query: query) } catch { self.error = error.localizedDescription }
        }
    }

    func activate(_ id: UUID? = nil) async {
        guard !isWorking else { return }
        guard !isLoading else {
            error = "Wait for the search results before opening a session."
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            if renameText != nil {
                try await rename()
                return
            }
            guard let target = id ?? selectedID,
                let selected = rows.first(where: { $0.id == target })
            else {
                throw SessionControlError.readOnly("This result changed. Select a session again.")
            }
            if purpose == .reference {
                try await reference(selected.id, query: query)
            } else {
                try await transition { try await controller.switchTo(selected.id) }
                close()
            }
        } catch { self.error = error.localizedDescription }
    }

    func reference(_ id: UUID, query: String = "") async throws {
        let fromPicker = isOpen
        guard let destination = controller.active?.id else {
            throw SessionControlError.readOnly("Open a destination session before attaching a reference.")
        }
        let request = generation
        guard id != controller.active?.id else {
            throw SessionControlError.readOnly("Choose another session to reference.")
        }
        let result = try await read.search(id, query: query)
        guard destination == controller.active?.id, request == generation, !Task.isCancelled else {
            throw SessionControlError.readOnly("The destination or search changed. Select the source again.")
        }
        guard !result.isEmpty else {
            throw SessionControlError.readOnly(
                "No matching readable excerpts. Try different words or a completed conversation.")
        }
        self.destination = destination
        referenceFromPicker = fromPicker
        referencePreview = result
        referenceScroll.scrollTo(edge: .top)
        isOpen = true
    }

    func attach() {
        guard !controller.isTransitioning else {
            error = "Wait for the current save before attaching excerpts."
            return
        }
        guard !controller.isReadOnly else {
            error = controller.readOnlyReason
            return
        }
        guard destination == controller.active?.id, let referencePreview else {
            error = "The destination session changed. Select the source again."
            return
        }
        let combined = controller.draft.references + referencePreview
        guard combined.count <= SessionReferences.countLimit,
            SessionReferences.render(combined).utf8.count <= SessionReferences.byteLimit
        else {
            error = "This draft already has excerpts. Use /unreference to remove them before attaching more."
            return
        }
        controller.draft.references = combined
        close()
    }

    func create() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await transition { try await controller.newSession() }
            close()
        } catch { self.error = error.localizedDescription }
    }

    private func transition(_ action: () async throws -> Void) async throws {
        if let editor { try await editor.transition(action) } else { try await action() }
    }

    func beginRename() {
        guard !isLoading else {
            error = "Wait for the search results before renaming."
            return
        }
        guard let selected else { return }
        renameID = selected.id
        renameText = selected.title
    }

    func cancelRename() {
        renameText = nil
        renameID = nil
    }

    func rename() async throws {
        guard let renameID, let renameText else { return }
        let selected = try await controller.store.summary(renameID)
        guard selected.workspace == controller.workspace else {
            throw SessionControlError.readOnly("Open Tag in this session's workspace to rename it.")
        }
        let owner =
            selected.id == controller.active?.id
            ? nil
            : try SessionOwnership(directory: controller.store.directory, sessionID: selected.id)
        guard selected.id != controller.active?.id || !controller.isReadOnly else {
            throw SessionControlError.readOnly(controller.readOnlyReason ?? "Read-only session.")
        }
        try await controller.store.rename(selected.id, title: renameText)
        if selected.id == controller.active?.id { controller.active = try await controller.store.summary(selected.id) }
        withExtendedLifetime(owner) {}
        cancelRename()
        await refresh()
    }

    /// Traps overlay keys; navigation never edits or sends the underlying draft.
    func handle(_ press: KeyPress) -> Bool {
        guard isOpen else { return false }
        guard press.phase != .up else { return true }
        let modifiers = press.modifiers.subtracting([.capsLock, .numLock])
        if press.key == .escape || (press.key == "c" && modifiers == .control) {
            if renameText != nil {
                cancelRename()
            } else if referencePreview != nil {
                dismissReference()
            } else {
                close()
            }
        } else if referencePreview != nil {
            handleReference(press)
        } else if renameText != nil {
            handleRename(press, modifiers: modifiers)
        } else {
            handlePicker(press, modifiers: modifiers)
        }
        return true
    }

    func dismissReference() {
        referencePreview = nil
        if !referenceFromPicker { close() }
    }

    private func handleReference(_ press: KeyPress) {
        switch press.key {
        case .return: attach()
        case .upArrow: referenceScroll.scrollBy(lines: -1)
        case .downArrow: referenceScroll.scrollBy(lines: 1)
        case .pageUp: referenceScroll.scrollBy(lines: -referencePageSize)
        case .pageDown: referenceScroll.scrollBy(lines: referencePageSize)
        case .home: referenceScroll.scrollTo(edge: .top)
        case .end: referenceScroll.scrollTo(edge: .bottom)
        default: break
        }
    }

    private func handleRename(_ press: KeyPress, modifiers: EventModifiers) {
        switch (press.key, modifiers) {
        case (.return, []): requestActivation()
        case (.backspace, []): backspace()
        case ("u", .control): renameText = ""
        case ("w", .control):
            var text = renameText ?? ""
            while text.last?.isWhitespace == true { text.removeLast() }
            while let last = text.last, !last.isWhitespace { text.removeLast() }
            renameText = text
        default: if let text = press.typedText { type(text) }
        }
    }

    private func handlePicker(_ press: KeyPress, modifiers: EventModifiers) {
        switch (press.key, modifiers) {
        case (.return, []): requestActivation()
        case (.backspace, []):
            backspace()
        case (.upArrow, []), ("k", .control): move(by: -1)
        case (.downArrow, []), ("j", .control): move(by: 1)
        case (.pageUp, []): move(by: -rowLimit)
        case (.pageDown, []): move(by: rowLimit)
        case (.tab, []): toggleScope()
        case ("n", .control): Task { await create() }
        case ("r", .control): beginRename()
        case ("l", .control):
            guard !isLoading else {
                error = "Wait for the search results before selecting a source."
                return
            }
            requestReference()
        default: if let text = press.typedText { type(text) }
        }
    }
}
