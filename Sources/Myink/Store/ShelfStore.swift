import AppKit
import MyinkCore
import Observation

/// Owns the shelf's state: every change goes through here, is saved (debounced, atomically) and
/// announced to observers. Also tracks runtime-only facts: file availability and failed imports.
@Observable
final class ShelfStore {
    private(set) var state: ShelfState
    /// Availability of referenced files, by item ID (refreshed when the shelf appears).
    private(set) var availability: [UUID: Availability] = [:]
    /// Placeholders whose import failed (shown with an error badge, then discarded).
    private(set) var failedItems: Set<UUID> = []

    @ObservationIgnored let layout: StorageLayout
    @ObservationIgnored let files: OwnedFileStore
    @ObservationIgnored let factory: ItemFactory
    @ObservationIgnored var preferences: () -> Preferences = { Preferences() }
    @ObservationIgnored private let manifest: ManifestStore
    @ObservationIgnored private var handlers: [() -> Void] = []
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    /// False when shelf.json was unreadable: its data folders must not be garbage-collected, so the
    /// quarantined manifest can still be recovered by hand.
    @ObservationIgnored private var loadedCleanly = true

    init(layout: StorageLayout = .applicationSupport()) {
        self.layout = layout
        files = OwnedFileStore(layout: layout)
        factory = ItemFactory(files: files)
        manifest = ManifestStore(layout: layout)
        try? layout.createDirectories()
        let result = manifest.load()
        state = result.state
        switch result {
        case .loaded:
            manifest.refreshBackup()
        case let .recovered(_, quarantined):
            loadedCleanly = quarantined == nil
            Log.store
                .error(
                    "shelf.json was unreadable (moved to \(quarantined?.lastPathComponent ?? "-", privacy: .public)); restored the backup"
                )
        case let .fresh(quarantined):
            loadedCleanly = quarantined == nil
            if let quarantined {
                Log.store.error("shelf.json was unreadable (moved to \(quarantined.lastPathComponent, privacy: .public)); starting empty")
            }
        }
        Log.store.info("loaded \(self.state.entries.count) entries, \(self.state.recentlyRemoved.count) recently removed")
    }

    // MARK: Observation

    func observe(_ handler: @escaping () -> Void) {
        handlers.append(handler)
    }

    private func notify() {
        for handler in handlers {
            handler()
        }
    }

    // MARK: Mutations

    /// Applies a change to the state, then saves and notifies.
    func mutate(_ body: (inout ShelfState) -> Void) {
        var copy = state
        body(&copy)
        guard copy != state else { return }
        state = copy
        scheduleSave()
        notify()
    }

    func add(_ entries: [ShelfEntry], at index: Int? = nil) {
        guard !entries.isEmpty else { return }
        mutate { $0.insert(entries, at: index) }
    }

    /// Removes into Recently Removed (one batch), then prunes old removals.
    @discardableResult
    func remove(_ selection: ItemSelection) -> [RemovedEntry] {
        var removed: [RemovedEntry] = []
        mutate { removed = $0.remove(selection) }
        pruneRecentlyRemoved()
        return removed
    }

    @discardableResult
    func clear(includingLocked: Bool) -> Int {
        var removed: [RemovedEntry] = []
        mutate { removed = $0.clear(includingLocked: includingLocked) }
        pruneRecentlyRemoved()
        return removed.count
    }

    @discardableResult
    func restoreLatestBatch() -> [UUID] {
        var restored: [UUID] = []
        mutate { restored = $0.restoreLatestBatch() }
        if !restored.isEmpty { refreshAvailability() }
        return restored
    }

    @discardableResult
    func restore(_ ids: Set<UUID>) -> [UUID] {
        var restored: [UUID] = []
        mutate { restored = $0.restore(ids) }
        if !restored.isEmpty { refreshAvailability() }
        return restored
    }

    /// Forgets items without recording them (failed imports), wherever they are, and deletes the
    /// data nothing else uses.
    func discard(_ selection: ItemSelection) {
        var orphaned: Set<String> = []
        mutate { orphaned = $0.discard(selection) }
        files.removeDirectories(orphaned)
        failedItems.subtract(selection.itemIDs)
    }

    /// Replaces a placeholder with the finished item — on the shelf or, if the user removed it while
    /// it was importing, in Recently Removed (so restoring it brings back the real item).
    func complete(placeholder id: UUID, with item: ShelfItem) {
        guard state.itemAnywhere(withID: id)?.isPlaceholder == true else {
            files.removeFiles(item.ownedRelativePaths) // discarded meanwhile; its folder may be shared
            return
        }
        failedItems.remove(id)
        mutate { $0.replaceItemAnywhere(id, with: item) }
    }

    /// Adds another finished item next to a placeholder's entry (extra files of one file promise).
    func append(_ item: ShelfItem, besideItem id: UUID) {
        guard state.itemAnywhere(withID: id) != nil else {
            files.removeFiles(item.ownedRelativePaths)
            return
        }
        mutate { $0.appendAnywhere([item], besideItem: id) }
    }

    /// Shows an import as failed, then forgets it a few seconds later (unless it completed after all).
    /// `directory` is the Items folder the import was writing into, deleted if nothing uses it.
    func markFailed(_ id: UUID, directory: String? = nil) {
        guard state.itemAnywhere(withID: id)?.isPlaceholder == true else { return }
        failedItems.insert(id)
        notify()
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard let self, failedItems.contains(id), state.itemAnywhere(withID: id)?.isPlaceholder == true else { return }
            discard(ItemSelection(itemIDs: [id]))
            if let directory, !state.referencedOwnedDirectories().contains(directory) {
                files.removeDirectories([directory])
            }
        }
    }

    func pruneRecentlyRemoved() {
        let preferences = preferences()
        var orphaned: Set<String> = []
        mutate {
            orphaned = $0.pruneRecentlyRemoved(
                now: Date(),
                maxCount: preferences.recentlyRemovedLimit,
                maxAge: preferences.recentlyRemovedMaxAge
            )
        }
        files.removeDirectories(orphaned)
    }

    /// Forgets everything in Recently Removed and deletes the data only it used.
    func emptyRecentlyRemoved() {
        var orphaned: Set<String> = []
        mutate { orphaned = $0.pruneRecentlyRemoved(now: Date(), maxCount: 0, maxAge: 0) }
        files.removeDirectories(orphaned)
    }

    /// Launch-time housekeeping: prune removals and delete unreferenced item directories.
    func performMaintenance() {
        pruneRecentlyRemoved()
        guard loadedCleanly else {
            Log.store.info("skipping cleanup of item folders: the shelf was restored from a backup")
            return
        }
        let deleted = files.collectGarbage(referenced: state.referencedOwnedDirectories(), minimumAge: 3600)
        if !deleted.isEmpty { Log.store.info("removed \(deleted.count) orphaned item folders") }
    }

    // MARK: Persistence

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    /// Writes the manifest now (on quit, SIGTERM, or after the debounce).
    func flush() {
        saveTask?.cancel()
        saveTask = nil
        do {
            try manifest.save(state)
        } catch {
            Log.store.error("saving shelf failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Files

    /// Where the item's file is (last known location for references; no disk access).
    func fileURL(for item: ShelfItem) -> URL? {
        switch item.content {
        case let .fileReference(reference): URL(filePath: reference.lastKnownPath)
        case let .ownedFile(file): files.url(for: file.relativePath)
        case .snippet, .placeholder: nil
        }
    }

    /// Resolves the item's file right now (following moves), for dragging out, opening or copying.
    func currentFileURL(for item: ShelfItem) -> URL? {
        switch item.content {
        case let .fileReference(reference):
            let resolution = Bookmarks.resolve(reference.bookmark, lastKnownPath: reference.lastKnownPath)
            if resolution.isStale, let url = resolution.url {
                updateReference(item.id, to: url)
            }
            if availability[item.id] != resolution.availability {
                availability[item.id] = resolution.availability
            }
            return resolution.url
        case let .ownedFile(file):
            let url = files.url(for: file.relativePath)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        case .snippet, .placeholder:
            return nil
        }
    }

    func data(for representation: Representation) -> Data? {
        try? Data(contentsOf: files.url(for: representation.relativePath))
    }

    func availability(of item: ShelfItem) -> Availability {
        switch item.content {
        case .fileReference: availability[item.id] ?? .available
        case let .ownedFile(file): FileManager.default.fileExists(atPath: files.url(for: file.relativePath).path) ? .available : .missing
        case .snippet, .placeholder: .available
        }
    }

    private func updateReference(_ id: UUID, to url: URL) {
        mutate { state in
            state.updateItem(id) { item in
                guard case var .fileReference(reference) = item.content else { return }
                reference.lastKnownPath = url.path
                if let bookmark = try? Bookmarks.create(for: url) { reference.bookmark = bookmark }
                item.content = .fileReference(reference)
                item.displayName = url.lastPathComponent
            }
        }
    }

    /// Re-resolves every referenced file off the main actor: follows moves/renames, updates
    /// availability badges and (optionally) removes deleted or trashed files.
    func refreshAvailability() {
        let references: [(UUID, Data, String)] = state.entries.flatMap(\.items).compactMap { item in
            guard case let .fileReference(reference) = item.content else { return nil }
            return (item.id, reference.bookmark, reference.lastKnownPath)
        }
        guard !references.isEmpty else { return }
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            let results = await Self.resolve(references)
            guard !Task.isCancelled else { return }
            self?.apply(results)
        }
    }

    @concurrent
    private static func resolve(_ references: [(UUID, Data, String)]) async -> [(UUID, Bookmarks.Resolution)] {
        references.map { ($0.0, Bookmarks.resolve($0.1, lastKnownPath: $0.2)) }
    }

    private func apply(_ results: [(UUID, Bookmarks.Resolution)]) {
        var newAvailability = availability
        for (id, resolution) in results {
            newAvailability[id] = resolution.availability
            if resolution.isStale, let url = resolution.url {
                updateReference(id, to: url)
            }
        }
        if newAvailability != availability {
            availability = newAvailability
            notify()
        }
        if preferences().autoRemoveMissing {
            let gone = results.filter { $0.1.availability == .missing || $0.1.availability == .inTrash }.map(\.0)
            if !gone.isEmpty { remove(ItemSelection(itemIDs: Set(gone))) }
        }
    }

    /// Items whose files are missing or trashed.
    var unavailableItemIDs: Set<UUID> {
        Set(availability.filter { $0.value == .missing || $0.value == .inTrash }.keys)
    }
}
