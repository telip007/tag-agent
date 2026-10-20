import Foundation
import Observation
import SessionKit
import Stipple

/// Local, user-directed discovery; it exposes no model-callable lookup tool.
@MainActor
@Observable
final class SessionFlow {
    enum Purpose { case browse, reference }

    @ObservationIgnored let controller: SessionController
    @ObservationIgnored let read: any SessionReadAccess
    @ObservationIgnored let editor: WorkspaceEditor?
    @ObservationIgnored var debounceDuration = Duration.milliseconds(30)
    var isOpen = false
    var purpose = Purpose.browse
    var query = ""
    var allWorkspaces = false
    var rows: [SessionSummary] = []
    var selectedID: UUID?
    var preview: [SessionReference] = []
    var referencePreview: [SessionReference]?
    var referenceScroll = ScrollPosition(edge: .top)
    var referencePageSize = 10
    var isLoading = false
    var isLoadingMore = false
    var isPreviewLoading = false
    var hasMore = false
    var error: String?
    var renameText: String?
    var renameID: UUID?
    var rowLimit = 6
    var isWorking = false
    @ObservationIgnored var destination: UUID?
    @ObservationIgnored var referenceFromPicker = false
    @ObservationIgnored private(set) var generation = 0
    @ObservationIgnored private var previewGeneration = 0
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var previewTask: Task<Void, Never>?

    init(controller: SessionController, read: (any SessionReadAccess)? = nil, editor: WorkspaceEditor? = nil) {
        self.controller = controller
        self.read = read ?? controller.store
        self.editor = editor
    }

    var selected: SessionSummary? { rows.first { $0.id == selectedID } }

    func open(purpose: Purpose = .browse) async {
        self.purpose = purpose
        destination = controller.active?.id
        query = ""
        allWorkspaces = false
        referencePreview = nil
        cancelRename()
        error = nil
        selectedID = controller.active?.id
        isOpen = true
        await refresh()
    }

    func close() {
        isOpen = false
        generation += 1
        previewGeneration += 1
        searchTask?.cancel()
        previewTask?.cancel()
    }

    func search(_ query: String) async {
        self.query = String(query.prefix(512))
        await refresh()
    }

    func refresh() async {
        generation += 1
        let request = generation
        isLoading = true
        error = nil
        do {
            let result = try await read.list(
                workspace: allWorkspaces ? nil : controller.workspace, query: query, after: nil, limit: 50)
            guard request == generation, isOpen, !Task.isCancelled else { return }
            rows = result
            hasMore = result.count == 50
            if !rows.contains(where: { $0.id == selectedID }) { selectedID = rows.first?.id }
            isLoading = false
            await loadPreview()
        } catch {
            guard request == generation, isOpen else { return }
            self.error = "Could not search sessions: \(error.localizedDescription)"
            isLoading = false
        }
    }

    func loadMore() async {
        guard hasMore, !isLoading, !isLoadingMore, let last = rows.last else { return }
        let request = generation
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let result = try await read.list(
                workspace: allWorkspaces ? nil : controller.workspace, query: query, after: SessionCursor(last),
                limit: 50)
            guard request == generation, isOpen, !Task.isCancelled else { return }
            let existing = Set(rows.map(\.id))
            rows += result.filter { !existing.contains($0.id) }
            hasMore = result.count == 50
        } catch { if request == generation { self.error = error.localizedDescription } }
    }

    func highlight(_ id: UUID) {
        guard rows.contains(where: { $0.id == id }) else { return }
        selectedID = id
        preview = []
        previewTask?.cancel()
        previewTask = Task { await loadPreview() }
    }

    func move(by offset: Int) {
        guard !rows.isEmpty else { return }
        let current = rows.firstIndex { $0.id == selectedID } ?? 0
        let index = max(0, min(rows.count - 1, current + offset))
        highlight(rows[index].id)
        if index >= rows.count - 5 { Task { await loadMore() } }
    }

    func window(limit: Int? = nil) -> Range<Int> {
        let rowLimit = max(1, limit ?? rowLimit)
        let index = rows.firstIndex { $0.id == selectedID } ?? 0
        let start = max(0, min(index - rowLimit / 2, rows.count - rowLimit))
        return start..<min(rows.count, start + rowLimit)
    }

    func loadPreview() async {
        previewGeneration += 1
        let request = previewGeneration
        guard let selected else {
            preview = []
            return
        }
        isPreviewLoading = true
        do {
            let result = try await read.search(selected.id, query: query)
            guard request == previewGeneration, selectedID == selected.id, isOpen, !Task.isCancelled else { return }
            preview = result
            isPreviewLoading = false
        } catch {
            guard request == previewGeneration, isOpen else { return }
            self.error = "Could not preview this session: \(error.localizedDescription)"
            isPreviewLoading = false
        }
    }

    func type(_ text: String) {
        if let renameText {
            self.renameText = String((renameText + text).prefix(80))
            return
        }
        query = String((query + text).prefix(512))
        scheduleSearch()
    }

    func backspace() {
        if var renameText {
            if !renameText.isEmpty { renameText.removeLast() }
            self.renameText = renameText
        } else if !query.isEmpty {
            query.removeLast()
            scheduleSearch()
        }
    }

    private func scheduleSearch() {
        isLoading = true
        generation += 1
        previewGeneration += 1
        previewTask?.cancel()
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: debounceDuration)
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }

    func toggleScope() {
        isLoading = true
        allWorkspaces.toggle()
        generation += 1
        previewGeneration += 1
        previewTask?.cancel()
        searchTask?.cancel()
        searchTask = Task { await refresh() }
    }
}
