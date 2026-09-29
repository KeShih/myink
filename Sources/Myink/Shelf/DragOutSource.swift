import AppKit
import MyinkCore

/// Runs drag sessions that take items off the shelf.
///
/// Files are offered as file URLs so Finder applies its own rules (move on the same volume, copy
/// across volumes, ⌥ copy, ⌘ move). Files Myink owns and snippets are copy-only, so the shelf's
/// copy survives. When the drop succeeds, dragged entries leave the shelf unless locked.
final class DragOutSource: NSObject, NSDraggingSource {
    private struct DraggedEntry {
        var entryID: UUID
        var itemIDs: [UUID]
        var isWholeEntry: Bool
        var isLocked: Bool
    }

    private struct ActiveDrag {
        var entries: [DraggedEntry]
        var kinds: Set<DragOutPolicy.Kind>
    }

    private let store: ShelfStore
    private let settings: SettingsStore
    private var active: ActiveDrag?

    /// Set by the shelf when the session ends on the shelf itself (a rearrangement, not a drag-out).
    var droppedOnShelf = false
    var onBegan: (() -> Void)?
    var onEnded: ((_ screenPoint: NSPoint, _ removedCount: Int) -> Void)?

    var isDragging: Bool {
        active != nil
    }

    init(store: ShelfStore, settings: SettingsStore) {
        self.store = store
        self.settings = settings
    }

    /// The item IDs being dragged (for internal drops).
    var draggedItemIDs: Set<UUID> {
        Set(active?.entries.flatMap(\.itemIDs) ?? [])
    }

    /// Entries dragged as a whole (for internal drops).
    var draggedWholeEntryIDs: [UUID] {
        active?.entries.filter(\.isWholeEntry).map(\.entryID) ?? []
    }

    /// Starts a drag for `rows`. `image` supplies each item's preview and `frame` each row's frame in `view`.
    @discardableResult
    func begin(
        rows: [RowID],
        event: NSEvent,
        from view: NSView,
        frame: (RowID) -> NSRect?,
        image: (ShelfItem) -> NSImage
    ) -> Bool {
        var draggingItems: [NSDraggingItem] = []
        var entries: [DraggedEntry] = []
        var kinds = Set<DragOutPolicy.Kind>()
        let state = store.state

        for row in rows {
            guard let entryIndex = state.entryIndex(withID: row.entryID) else { continue }
            let entry = state.entries[entryIndex]
            let candidates: [ShelfItem] = switch row {
            case .entry: entry.items
            case let .child(_, itemID): entry.items.filter { $0.id == itemID }
            }
            var draggedIDs: [UUID] = []
            let rowFrame = frame(row) ?? .zero
            for item in candidates {
                guard let (writer, kind) = pasteboardWriter(for: item) else { continue }
                let draggingItem = NSDraggingItem(pasteboardWriter: writer)
                let preview = image(item)
                let side = min(rowFrame.width, rowFrame.height) * 0.62
                let offset = CGFloat(draggedIDs.count) * 4
                let previewFrame = NSRect(x: rowFrame.midX - side / 2 + offset, y: rowFrame.minY + 6 + offset, width: side, height: side)
                draggingItem.setDraggingFrame(previewFrame, contents: preview)
                draggingItems.append(draggingItem)
                draggedIDs.append(item.id)
                kinds.insert(kind)
            }
            guard !draggedIDs.isEmpty else { continue }
            if let existing = entries.firstIndex(where: { $0.entryID == entry.id }) {
                entries[existing].itemIDs += draggedIDs
                entries[existing].isWholeEntry = Set(entries[existing].itemIDs) == Set(entry.items.map(\.id))
            } else {
                let whole = draggedIDs.count == entry.items.count
                entries.append(DraggedEntry(entryID: entry.id, itemIDs: draggedIDs, isWholeEntry: whole, isLocked: entry.isLocked))
            }
        }

        guard !draggingItems.isEmpty else {
            NSSound.beep()
            return false
        }
        active = ActiveDrag(entries: entries, kinds: kinds)
        droppedOnShelf = false
        let session = view.beginDraggingSession(with: draggingItems, event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = draggingItems.count > 1 ? .pile : .none
        onBegan?()
        Log.export
            .debug(
                "drag out began: \(draggingItems.count) item(s), kinds \(kinds.map { "\($0)" }.joined(separator: ","), privacy: .public)"
            )
        return true
    }

    private func pasteboardWriter(for item: ShelfItem) -> (any NSPasteboardWriting, DragOutPolicy.Kind)? {
        switch item.content {
        case .fileReference:
            guard let url = store.currentFileURL(for: item) else { return nil }
            return (url as NSURL, .reference)
        case .ownedFile:
            guard let url = store.currentFileURL(for: item) else { return nil }
            return (url as NSURL, .owned)
        case let .snippet(snippet):
            return (SnippetPasteboardBuilder.pasteboardItem(for: snippet, load: store.data(for:)), .snippet)
        case .placeholder:
            return nil
        }
    }

    // MARK: NSDraggingSource

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        DragOutPolicy.sourceMask(for: active?.kinds ?? [.snippet], isLocal: context == .withinApplication)
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        false
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        guard let active else { return }
        self.active = nil
        let outcome = DragOutPolicy.outcome(of: operation)
        let preferences = settings.preferences
        let fnHeld = NSEvent.modifierFlags.contains(.function)
        var selection = ItemSelection()
        for entry in active.entries {
            let remove = DragOutPolicy.shouldRemove(
                outcome: outcome,
                isLocked: entry.isLocked,
                keepAfterDragOut: preferences.keepAfterDragOut,
                fnHeld: fnHeld,
                droppedOnShelf: droppedOnShelf
            )
            guard remove else { continue }
            if entry.isWholeEntry {
                selection.entryIDs.insert(entry.entryID)
            } else {
                selection.itemIDs.formUnion(entry.itemIDs)
            }
        }
        let removed = selection.isEmpty ? [] : store.remove(selection)
        let outcomeName = String(describing: outcome)
        Log.export.info("drag out ended: \(outcomeName, privacy: .public), removed \(removed.count) entries")
        droppedOnShelf = false
        if outcome == .moved { store.refreshAvailability() }
        onEnded?(screenPoint, removed.count)
    }
}
