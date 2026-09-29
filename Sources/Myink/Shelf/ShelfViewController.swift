import AppKit
import MyinkCore
import QuickLookUI

/// The shelf's content: shows the store's entries, handles drops onto the shelf, drags off it,
/// keyboard commands, the context menu and Quick Look. Visibility is the window controller's job;
/// this controller reports the events it needs through the `on…` callbacks.
final class ShelfViewController: NSViewController {
    // Callbacks to the window controller.
    var onContentLengthChanged: (() -> Void)?
    var onPointerEntered: (() -> Void)?
    var onPointerExited: (() -> Void)?
    var onDropCompleted: (() -> Void)?
    var onInternalDragBegan: (() -> Void)?
    var onInternalDragEnded: ((_ pointerInside: Bool) -> Void)?
    var onCancel: (() -> Void)?
    /// Builds the ⋯ / status-item menu (Recently Removed, Settings…).
    var appMenuProvider: (() -> NSMenu)?

    private let store: ShelfStore
    private let settings: SettingsStore
    private let importer: ImportCoordinator
    let dragOut: DragOutSource
    private let thumbnails = ThumbnailProvider()
    private let quickLook = QuickLookCoordinator()
    private lazy var previews = PreviewMaterializer(store: store)
    private let list: ShelfListView
    private lazy var container = ShelfContainerView(list: list)
    private var expanded: Set<UUID> = []
    /// Cell images keyed by `imageKey(for:)`, so a finished import, a rename or a size change
    /// (all of which change the key) gets a fresh thumbnail.
    private var images: [String: NSImage] = [:]
    private var imageRequests: Set<String> = []
    /// Rows whose Quick Look URLs are shown, parallel to the URLs (for the zoom animation).
    private var previewRows: [RowID] = []
    private var dragIsInternal = false

    init(store: ShelfStore, settings: SettingsStore, importer: ImportCoordinator) {
        self.store = store
        self.settings = settings
        self.importer = importer
        dragOut = DragOutSource(store: store, settings: settings)
        list = ShelfListView(layout: Self.layout(for: settings.preferences))
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    static func layout(for preferences: Preferences) -> ShelfLayout {
        ShelfLayout(isVertical: preferences.edge.isVertical, metrics: .metrics(for: preferences.size))
    }

    override func loadView() {
        let root = ShelfBackgroundView()
        root.contentView = container
        view = root
        container.delegate = self
        list.delegate = self
        container.header.onClear = { [weak self] includingLocked in self?.clear(includingLocked: includingLocked) }
        container.header.onMenu = { [weak self] button in
            guard let menu = self?.appMenuProvider?() else { return }
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
        }
        dragOut.onBegan = { [weak self] in self?.onInternalDragBegan?() }
        dragOut.onEnded = { [weak self] point, _ in
            guard let self else { return }
            let inside = view.window.map { NSMouseInRect(point, $0.frame, false) } ?? false
            onInternalDragEnded?(inside)
        }
        quickLook.onKeyDown = { [weak self] event in self?.handleQuickLookKey(event) ?? false }
        quickLook.sourceFrame = { [weak self] index in self?.quickLookSourceFrame(index) ?? .zero }
        importer.onDuplicate = { [weak self] entryID in self?.flash(entryID) }
        applyPreferences()
        reload(animated: false)
    }

    // MARK: Model → view

    /// Length along the edge the shelf needs for all its content (header + rows), for sizing the panel.
    var contentLength: CGFloat {
        let layout = list.layoutModel
        let rows = max(layout.contentLength(for: list.rows), layout.metrics.cellLength + 2 * layout.metrics.padding)
        return rows + layout.metrics.headerLength
    }

    var thickness: CGFloat {
        list.layoutModel.metrics.thickness
    }

    func applyPreferences() {
        let layout = Self.layout(for: settings.preferences)
        container.isVertical = layout.isVertical
        container.headerLength = layout.metrics.headerLength
        list.layoutModel = layout
        onContentLengthChanged?()
    }

    func reload(animated: Bool) {
        let entries = store.state.entries
        expanded.formIntersection(entries.filter(\.isStack).map(\.id))
        let rows = ShelfRows.rows(for: entries, expanded: expanded)
        list.setRows(rows, animated: animated)
        container.header.set(itemCount: store.state.itemCount)
        container.emptyLabel.isHidden = !entries.isEmpty
        let liveKeys = Set(entries.flatMap(\.items).map(imageKey(for:)))
        images = images.filter { liveKeys.contains($0.key) }
        imageRequests.formIntersection(liveKeys)
        updateQuickLookIfVisible()
        onContentLengthChanged?()
    }

    /// Re-renders cells without changing rows (availability or failures changed).
    func refreshCells() {
        list.reconfigureCells()
    }

    private func imageKey(for item: ShelfItem) -> String {
        "\(item.id)-\(item.content.hashValue)-\(item.displayName.hashValue)-\(Int(list.layoutModel.metrics.thumbnailSize))"
    }

    private func image(for item: ShelfItem) -> NSImage {
        let size = list.layoutModel.metrics.thumbnailSize
        let key = imageKey(for: item)
        if let cached = images[key] { return cached }
        let url = store.fileURL(for: item)
        let immediate = thumbnails.immediateImage(for: item, url: url, size: size)
        images[key] = immediate
        if item.isFileBacked, store.availability(of: item) == .available, !imageRequests.contains(key) {
            imageRequests.insert(key)
            let scale = view.window?.backingScaleFactor ?? 2
            thumbnails.thumbnail(for: item, url: url, size: size, scale: scale) { [weak self] image in
                guard let self, imageRequests.contains(key) else { return }
                images[key] = image
                list.reconfigureCellsShowing(itemID: item.id, in: store.state)
            }
        }
        return immediate
    }

    private func status(of items: [ShelfItem]) -> ShelfCellView.Model.Status {
        if items.contains(where: { store.failedItems.contains($0.id) }) { return .failed }
        if items.contains(where: \.isPlaceholder) { return .pending }
        let availability = items.map(store.availability(of:))
        if availability.contains(.missing) { return .missing }
        if availability.contains(.offline) { return .offline }
        if availability.contains(.inTrash) { return .inTrash }
        return .normal
    }

    // MARK: Actions

    /// The items behind rows, each once (⌘A selects a stack's row and its expanded child rows).
    private func items(for rows: [RowID]) -> [ShelfItem] {
        itemsWithRows(for: rows).map(\.item)
    }

    private func itemsWithRows(for rows: [RowID]) -> [(item: ShelfItem, row: RowID)] {
        var result: [(item: ShelfItem, row: RowID)] = []
        var seen = Set<UUID>()
        for row in rows {
            guard let index = store.state.entryIndex(withID: row.entryID) else { continue }
            let entry = store.state.entries[index]
            let candidates: [ShelfItem] = switch row {
            case .entry: entry.items
            case let .child(_, itemID): entry.items.filter { $0.id == itemID }
            }
            for item in candidates where seen.insert(item.id).inserted {
                result.append((item, row))
            }
        }
        return result
    }

    private func selection(for rows: [RowID]) -> ItemSelection {
        var selection = ItemSelection()
        for row in rows {
            switch row {
            case let .entry(id): selection.entryIDs.insert(id)
            case let .child(entryID, itemID): if !selection.entryIDs.contains(entryID) { selection.itemIDs.insert(itemID) }
            }
        }
        return selection
    }

    func remove(_ rows: [RowID]) {
        let selection = selection(for: rows)
        guard !selection.isEmpty else { return }
        store.remove(selection)
    }

    func clear(includingLocked: Bool) {
        store.clear(includingLocked: includingLocked)
    }

    func open(_ rows: [RowID]) {
        for item in items(for: rows) {
            switch item.content {
            case let .snippet(snippet) where snippet.kind == .link:
                if let link = snippet.url.flatMap(URL.init(string:)) { NSWorkspace.shared.open(link) }
            default:
                if let url = previews.url(for: item) { NSWorkspace.shared.open(url) } else { NSSound.beep() }
            }
        }
    }

    func revealInFinder(_ rows: [RowID]) {
        let urls = items(for: rows).compactMap { item in item.isFileBacked ? store.currentFileURL(for: item) : nil }
        if urls.isEmpty { NSSound.beep() } else { NSWorkspace.shared.activateFileViewerSelecting(urls) }
    }

    func copy(_ rows: [RowID]) {
        let writers: [any NSPasteboardWriting] = items(for: rows).compactMap { item in
            switch item.content {
            case .fileReference, .ownedFile: store.currentFileURL(for: item).map { $0 as NSURL }
            case let .snippet(snippet): SnippetPasteboardBuilder.pasteboardItem(for: snippet, load: store.data(for:))
            case .placeholder: nil
            }
        }
        guard !writers.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(writers)
    }

    func toggleLock(_ rows: [RowID]) {
        let ids = Set(rows.map(\.entryID))
        let lock = !store.state.entries.filter { ids.contains($0.id) }.allSatisfy(\.isLocked)
        store.mutate { $0.setLocked(lock, entries: ids) }
    }

    func toggleExpanded(_ entryID: UUID) {
        if expanded.contains(entryID) { expanded.remove(entryID) } else { expanded.insert(entryID) }
        reload(animated: true)
    }

    func rename(_ row: RowID) {
        guard let item = items(for: [row]).first, !item.isPlaceholder else { return }
        let alert = NSAlert()
        alert.messageText = "Rename"
        alert.informativeText = item.isSnippet ? "Choose a name for this snippet." : "Choose a new name for Myink's copy of this file."
        let field = NSTextField(string: item.displayName)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let newName = FileNaming.sanitized(field.stringValue, fallback: item.displayName)
        switch item.content {
        case let .ownedFile(file):
            let url = store.files.url(for: file.relativePath)
            let destination = url.deletingLastPathComponent().appending(path: newName)
            do {
                try FileManager.default.moveItem(at: url, to: destination)
                let directory = (file.relativePath as NSString).deletingLastPathComponent
                store.mutate { state in
                    state.updateItem(item.id) {
                        $0.displayName = newName
                        $0.content = .ownedFile(OwnedFile(relativePath: "\(directory)/\(newName)", origin: file.origin))
                    }
                }
                images = images.filter { !$0.key.hasPrefix(item.id.uuidString) }
            } catch {
                NSAlert(error: error).runModal()
            }
        case .snippet:
            store.mutate { $0.updateItem(item.id) { $0.displayName = newName } }
        case .fileReference, .placeholder:
            break
        }
    }

    func stack(_ rows: [RowID]) {
        let ids = Set(rows.compactMap { row -> UUID? in if case let .entry(id) = row { id } else { nil } })
        guard ids.count > 1 else { return }
        store.mutate { $0.merge(ids) }
    }

    func split(_ entryID: UUID) {
        expanded.remove(entryID)
        store.mutate { $0.split(entryID) }
    }

    func removeMissing() {
        let missing = store.unavailableItemIDs
        guard !missing.isEmpty else { return }
        store.remove(ItemSelection(itemIDs: missing))
    }

    func selectAll() {
        list.selectAllRows()
    }

    /// The view that should receive keystrokes when the shelf becomes key.
    var firstResponderView: NSView? {
        list
    }

    /// A drop onto the collapsed edge tab: import at the top.
    func importDropFromTab(_ info: any NSDraggingInfo) -> Bool {
        let added = importer.importPasteboard(info.draggingPasteboard, at: 0, allowPromises: true)
        onDropCompleted?()
        return added > 0
    }

    /// Scrolls to and briefly highlights an entry (e.g. a file that was dropped twice).
    func flash(_ entryID: UUID) {
        guard let cell = list.cell(for: .entry(entryID)), let frame = list.frame(for: .entry(entryID)) else { return }
        list.scrollToVisible(frame)
        cell.isDropTarget = true
        Task { [weak cell] in
            try? await Task.sleep(for: .milliseconds(600))
            cell?.isDropTarget = false
        }
    }

    // MARK: Quick Look

    /// Preview URLs for the selection, remembering which row each came from.
    private func selectedPreviewURLs() -> [URL] {
        var urls: [URL] = []
        var rows: [RowID] = []
        for (item, row) in itemsWithRows(for: list.selectedRows) {
            guard let url = previews.url(for: item) else { continue }
            urls.append(url)
            rows.append(row)
        }
        previewRows = rows
        return urls
    }

    /// Keeps an open Quick Look panel in sync (skipped when closed: resolving URLs touches the disk).
    private func updateQuickLookIfVisible() {
        guard quickLook.isVisible else { return }
        quickLook.update(urls: selectedPreviewURLs())
    }

    func toggleQuickLook() {
        view.window?.makeKey()
        view.window?.makeFirstResponder(list)
        quickLook.level = view.window?.level ?? .statusBar
        quickLook.toggle(urls: selectedPreviewURLs())
    }

    func closeQuickLook() {
        quickLook.close()
    }

    private func handleQuickLookKey(_ event: NSEvent) -> Bool {
        // Arrows along the list move the selection; the other two page within Quick Look.
        let listArrows: Set<Int> = list.layoutModel.isVertical ? [125, 126] : [123, 124]
        switch Int(event.keyCode) {
        case let code where listArrows.contains(code):
            list.keyDown(with: event)
            return true
        case 49, 53:
            quickLook.close()
            return true
        default:
            return false
        }
    }

    private func quickLookSourceFrame(_ index: Int) -> NSRect {
        guard previewRows.indices.contains(index), let frame = list.frame(for: previewRows[index]),
              let window = view.window else { return .zero }
        return window.convertToScreen(list.convert(frame, to: nil))
    }

    // Quick Look's panel-controller hooks are declared nonisolated; AppKit calls them on the main thread.
    override nonisolated func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        true
    }

    override nonisolated func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated { quickLook.begin(panel) }
    }

    override nonisolated func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated { quickLook.end(panel) }
    }

    // MARK: Context menu

    private func contextMenu(for rows: [RowID]) -> NSMenu? {
        guard !rows.isEmpty else { return appMenuProvider?() }
        let items = items(for: rows).filter { !$0.isPlaceholder }
        guard !items.isEmpty else { return nil }
        let menu = NSMenu()
        let fileURLs = items.filter(\.isFileBacked).compactMap(store.fileURL(for:))
        menu.addItem(ClosureMenuItem("Open") { [weak self] in self?.open(rows) })
        if items.count == 1, let url = fileURLs.first {
            let openWith = NSMenuItem(title: "Open With", action: nil, keyEquivalent: "")
            openWith.submenu = openWithMenu(for: url)
            menu.addItem(openWith)
        }
        if !fileURLs.isEmpty {
            menu.addItem(ClosureMenuItem("Show in Finder") { [weak self] in self?.revealInFinder(rows) })
        }
        menu.addItem(ClosureMenuItem("Quick Look", key: " ") { [weak self] in self?.toggleQuickLook() })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Copy", key: "c") { [weak self] in self?.copy(rows) })
        let shareURLs = items.compactMap(previews.url(for:))
        if !shareURLs.isEmpty {
            let share = NSSharingServicePicker(items: shareURLs).standardShareMenuItem
            menu.addItem(share)
        }
        menu.addItem(.separator())
        let entryIDs = Set(rows.map(\.entryID))
        let allLocked = store.state.entries.filter { entryIDs.contains($0.id) }.allSatisfy(\.isLocked)
        menu.addItem(ClosureMenuItem(allLocked ? "Unlock" : "Lock") { [weak self] in self?.toggleLock(rows) })
        if rows.count == 1, case let .entry(id) = rows[0], let entry = store.state.entries.first(where: { $0.id == id }), entry.isStack {
            menu
                .addItem(ClosureMenuItem(expanded.contains(id) ? "Collapse Stack" : "Expand Stack") { [weak self] in
                    self?.toggleExpanded(id)
                })
            menu.addItem(ClosureMenuItem("Split Stack") { [weak self] in self?.split(id) })
        }
        let entryRows = rows.filter { if case .entry = $0 { true } else { false } }
        if entryRows.count > 1 {
            menu.addItem(ClosureMenuItem("Stack Together") { [weak self] in self?.stack(entryRows) })
        }
        if rows.count == 1, let item = items.first, items.count == 1 {
            switch item.content {
            case .ownedFile, .snippet: menu.addItem(ClosureMenuItem("Rename…") { [weak self] in self?.rename(rows[0]) })
            default: break
            }
        }
        menu.addItem(.separator())
        let remove = ClosureMenuItem("Remove from Shelf") { [weak self] in self?.remove(rows) }
        remove.keyEquivalent = "\u{8}"
        remove.keyEquivalentModifierMask = []
        menu.addItem(remove)
        if !store.unavailableItemIDs.isEmpty {
            menu.addItem(ClosureMenuItem("Remove Missing Items") { [weak self] in self?.removeMissing() })
        }
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Clear Shelf") { [weak self] in self?.clear(includingLocked: false) })
        let clearAll = ClosureMenuItem("Clear Shelf Including Locked") { [weak self] in self?.clear(includingLocked: true) }
        clearAll.isAlternate = true
        clearAll.keyEquivalentModifierMask = .option
        menu.addItem(clearAll)
        return menu
    }

    private func openWithMenu(for url: URL) -> NSMenu {
        let menu = NSMenu()
        let apps = NSWorkspace.shared.urlsForApplications(toOpen: url).prefix(20)
        for app in apps {
            let item = ClosureMenuItem(FileManager.default.displayName(atPath: app.path)) {
                NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
            }
            let icon = NSWorkspace.shared.icon(forFile: app.path)
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            menu.addItem(item)
        }
        if apps.isEmpty { menu.addItem(NSMenuItem(title: "No Applications", action: nil, keyEquivalent: "")) }
        return menu
    }
}

// MARK: - List delegate

extension ShelfViewController: ShelfListViewDelegate {
    func listView(_ list: ShelfListView, configure cell: ShelfCellView, for row: RowID) {
        guard let index = store.state.entryIndex(withID: row.entryID) else { return }
        let entry = store.state.entries[index]
        let model: ShelfCellView.Model
        switch row {
        case .entry:
            let title = entry.isStack ? "\(entry.items.count) Items" : entry.items.first?.displayName ?? ""
            let tip = entry.isStack ? entry.items.map(\.displayName).joined(separator: "\n") : entry.items.first.map(tooltip(for:))
            model = ShelfCellView.Model(
                title: title,
                images: entry.items.prefix(3).map(image(for:)),
                itemCount: entry.items.count,
                isLocked: entry.isLocked,
                isChild: false,
                isExpanded: expanded.contains(entry.id),
                status: status(of: entry.items),
                toolTip: tip
            )
        case let .child(_, itemID):
            guard let item = entry.items.first(where: { $0.id == itemID }) else { return }
            model = ShelfCellView.Model(
                title: item.displayName,
                images: [image(for: item)],
                itemCount: 1,
                isLocked: entry.isLocked,
                isChild: true,
                isExpanded: false,
                status: status(of: [item]),
                toolTip: tooltip(for: item)
            )
        }
        cell.apply(model)
        cell.onToggleLock = { [weak self] all in
            if all { self?.store.mutate { $0.toggleAllLocks() } } else { self?.toggleLock([.entry(entry.id)]) }
        }
        cell.onRemove = { [weak self] in self?.remove([row]) }
        cell.onToggleExpand = { [weak self] in self?.toggleExpanded(entry.id) }
    }

    private func tooltip(for item: ShelfItem) -> String {
        switch item.content {
        case let .fileReference(reference): reference.lastKnownPath
        case let .snippet(snippet): snippet.url ?? String((snippet.previewText ?? item.displayName).prefix(300))
        case .ownedFile, .placeholder: item.displayName
        }
    }

    func listView(_ list: ShelfListView, beginDragOf rows: [RowID], event: NSEvent) {
        quickLook.close()
        dragOut.begin(rows: rows, event: event, from: list, frame: { list.frame(for: $0) }, image: { [weak self] in
            self?.image(for: $0) ?? NSImage()
        })
    }

    func listView(_ list: ShelfListView, open row: RowID) {
        if case let .entry(id) = row, store.state.entries.first(where: { $0.id == id })?.isStack == true {
            toggleExpanded(id)
        } else {
            open([row])
        }
    }

    func listView(_ list: ShelfListView, menuFor rows: [RowID]) -> NSMenu? {
        contextMenu(for: rows)
    }

    func listViewSelectionDidChange(_ list: ShelfListView) {
        updateQuickLookIfVisible()
    }

    func listViewQuickLook(_ list: ShelfListView) {
        toggleQuickLook()
    }

    func listViewDelete(_ list: ShelfListView) {
        remove(list.selectedRows)
    }

    func listViewCancel(_ list: ShelfListView) {
        if quickLook.isVisible { quickLook.close() } else { onCancel?() }
    }

    func listViewCopy(_ list: ShelfListView) {
        copy(list.selectedRows)
    }

    func listViewPaste(_ list: ShelfListView) {
        importer.importPasteboard(.general, at: 0)
    }
}

// MARK: - Drop target

extension ShelfViewController: ShelfContainerDelegate {
    private func isInternal(_ info: any NSDraggingInfo) -> Bool {
        (info.draggingSource as AnyObject?) === dragOut && dragOut.isDragging
    }

    private func updateDrop(_ info: any NSDraggingInfo) -> NSDragOperation {
        let fromShelf = isInternal(info)
        let point = list.convert(info.draggingLocation, from: nil)
        list.dropTarget = list.dropTarget(at: point, allowOnto: fromShelf)
        container.isHighlighted = !fromShelf
        return DropPolicy.operation(sourceMask: info.draggingSourceOperationMask, isInternal: fromShelf)
    }

    func containerDraggingEntered(_ info: any NSDraggingInfo) -> NSDragOperation {
        dragIsInternal = isInternal(info)
        onPointerEntered?()
        return updateDrop(info)
    }

    func containerDraggingUpdated(_ info: any NSDraggingInfo) -> NSDragOperation {
        updateDrop(info)
    }

    func containerDraggingExited() {
        list.dropTarget = nil
        container.isHighlighted = false
    }

    func containerPerformDrop(_ info: any NSDraggingInfo) -> Bool {
        let target = list.dropTarget ?? .between(0)
        list.dropTarget = nil
        container.isHighlighted = false
        if isInternal(info) {
            dragOut.droppedOnShelf = true
            performInternalDrop(target)
            return true
        }
        let index = entryIndex(forRowIndex: target)
        let added = importer.importPasteboard(info.draggingPasteboard, at: index, allowPromises: true)
        onDropCompleted?()
        return added > 0
    }

    /// Entry index for a drop between rows (rows of expanded stacks don't count as entries).
    private func entryIndex(forRowIndex target: ShelfLayout.DropTarget) -> Int {
        let rowIndex: Int = switch target {
        case let .between(index), let .onto(index): index
        }
        return list.rows.prefix(rowIndex).count { if case .entry = $0 { true } else { false } }
    }

    /// Rearranges the shelf after a drag from the shelf onto itself: onto a row merges into that
    /// entry (making a stack); between rows moves whole entries or pulls items out of stacks.
    private func performInternalDrop(_ target: ShelfLayout.DropTarget) {
        let wholeEntries = dragOut.draggedWholeEntryIDs
        let wholeItemIDs = Set(wholeEntries.flatMap { id in store.state.entries.first { $0.id == id }?.items.map(\.id) ?? [] })
        let looseItems = dragOut.draggedItemIDs.subtracting(wholeItemIDs)
        switch target {
        case let .onto(rowIndex):
            guard list.rows.indices.contains(rowIndex) else { return }
            let targetEntry = list.rows[rowIndex].entryID
            guard !wholeEntries.contains(targetEntry) else { return } // dropped onto itself
            store.mutate { state in
                if !wholeEntries.isEmpty { state.merge(Set(wholeEntries + [targetEntry])) }
                if !looseItems.isEmpty { state.moveItems(looseItems, intoEntry: targetEntry) }
            }
        case .between:
            let index = entryIndex(forRowIndex: target)
            store.mutate { state in
                if !wholeEntries.isEmpty { state.move(wholeEntries, to: index) }
                if !looseItems.isEmpty { state.extractItems(looseItems, toNewEntryAt: index) }
            }
        }
    }

    func containerPointerEntered() {
        onPointerEntered?()
    }

    func containerPointerExited() {
        onPointerExited?()
    }
}

// MARK: - Helpers

/// A menu item that runs a closure (menus invoke actions on the main thread).
final nonisolated class ClosureMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(_ title: String, key: String = "", handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: key)
        target = self
        if key == " " { keyEquivalentModifierMask = [] }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func run() {
        let handler = handler
        MainActor.assumeIsolated { handler() }
    }
}

extension ShelfListView {
    /// Reconfigures only the rows that display `itemID` (after its thumbnail arrived).
    func reconfigureCellsShowing(itemID: UUID, in state: ShelfState) {
        guard let entryIndex = state.entryIndex(containingItem: itemID) else { return }
        let entryID = state.entries[entryIndex].id
        for row in rows where row == .entry(entryID) || row == .child(entry: entryID, item: itemID) {
            if let cell = cell(for: row) { delegate?.listView(self, configure: cell, for: row) }
        }
    }
}

/// Rounded Liquid Glass background hosting the shelf content.
final class ShelfBackgroundView: NSView {
    private let glass = NSGlassEffectView()
    var contentView: NSView? {
        didSet {
            oldValue?.removeFromSuperview()
            guard let contentView else { return }
            contentView.frame = bounds
            contentView.autoresizingMask = [.width, .height]
            addSubview(contentView)
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        glass.cornerRadius = 16
        glass.frame = bounds
        glass.autoresizingMask = [.width, .height]
        addSubview(glass)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}
