import AppKit
import MyinkCore

protocol ShelfListViewDelegate: AnyObject {
    func listView(_ list: ShelfListView, configure cell: ShelfCellView, for row: RowID)
    func listView(_ list: ShelfListView, beginDragOf rows: [RowID], event: NSEvent)
    func listView(_ list: ShelfListView, open row: RowID)
    func listView(_ list: ShelfListView, menuFor rows: [RowID]) -> NSMenu?
    func listViewSelectionDidChange(_ list: ShelfListView)
    func listViewQuickLook(_ list: ShelfListView)
    func listViewDelete(_ list: ShelfListView)
    func listViewCancel(_ list: ShelfListView)
    func listViewCopy(_ list: ShelfListView)
    func listViewPaste(_ list: ShelfListView)
}

/// The scrolling list of cells. Custom rather than NSCollectionView so a stack can be dragged as many
/// items, drags start on the first click in a non-activating panel, and layout/selection stay in
/// testable Core types (`ShelfLayout`, `SelectionModel`).
final class ShelfListView: NSView {
    weak var delegate: ShelfListViewDelegate?

    var layoutModel: ShelfLayout {
        didSet { if layoutModel != oldValue { relayout(animated: false) } }
    }

    private(set) var rows: [RowID] = []
    private(set) var frames: [CGRect] = []
    private var cells: [RowID: ShelfCellView] = [:]
    private(set) var selection = SelectionModel()
    private let insertionIndicator = NSView()

    var dropTarget: ShelfLayout.DropTarget? {
        didSet { if dropTarget != oldValue { updateDropIndicator() } }
    }

    // Mouse tracking state.
    private var mouseDownRow: RowID?
    private var mouseDownPoint: NSPoint = .zero
    private var selectOnMouseUp: RowID?
    /// A ⌘-click on a selected row deselects it on mouse-up, unless it becomes a drag of the selection.
    private var toggleOnMouseUp: RowID?
    private var dragStarted = false

    init(layout: ShelfLayout) {
        layoutModel = layout
        super.init(frame: .zero)
        insertionIndicator.wantsLayer = true
        insertionIndicator.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        insertionIndicator.layer?.cornerRadius = 1.5
        insertionIndicator.isHidden = true
        addSubview(insertionIndicator)
        setAccessibilityRole(.list)
        setAccessibilityLabel("Shelf")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool {
        true
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    /// Everything except the cells' buttons is handled by the list itself.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        if hit is NSButton { return hit }
        return hit == nil ? nil : self
    }

    // MARK: Rows

    func setRows(_ newRows: [RowID], animated: Bool) {
        let removed = Set(rows).subtracting(newRows)
        for row in removed {
            guard let cell = cells.removeValue(forKey: row) else { continue }
            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.15
                    cell.animator().alphaValue = 0
                } completionHandler: {
                    MainActor.assumeIsolated { cell.removeFromSuperview() }
                }
            } else {
                cell.removeFromSuperview()
            }
        }
        var added: [ShelfCellView] = []
        for row in newRows where cells[row] == nil {
            let cell = ShelfCellView()
            cell.thumbnailSize = layoutModel.metrics.thumbnailSize
            cells[row] = cell
            addSubview(cell, positioned: .below, relativeTo: insertionIndicator)
            added.append(cell)
        }
        rows = newRows
        reconfigureCells()
        selection.prune(keeping: rows)
        relayout(animated: animated, newCells: added)
        refreshSelection()
    }

    func reconfigureCells() {
        for row in rows {
            if let cell = cells[row] { delegate?.listView(self, configure: cell, for: row) }
        }
    }

    func cell(for row: RowID) -> ShelfCellView? {
        cells[row]
    }

    func frame(for row: RowID) -> NSRect? {
        rows.firstIndex(of: row).map { frames[$0] }
    }

    func relayout(animated: Bool, newCells: [ShelfCellView] = []) {
        frames = layoutModel.frames(for: rows)
        let length = layoutModel.contentLength(for: rows)
        let clip = enclosingScrollView?.contentView.bounds.size ?? .zero
        let size = layoutModel.isVertical
            ? NSSize(width: max(clip.width, layoutModel.metrics.thickness), height: max(length, clip.height))
            : NSSize(width: max(length, clip.width), height: max(clip.height, layoutModel.metrics.thickness))
        setFrameSize(size)
        let newSet = Set(newCells.map(ObjectIdentifier.init))
        for (row, frame) in zip(rows, frames) {
            guard let cell = cells[row] else { continue }
            cell.thumbnailSize = layoutModel.metrics.thumbnailSize
            if animated, !newSet.contains(ObjectIdentifier(cell)) {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.18
                    context.allowsImplicitAnimation = true
                    cell.animator().frame = frame
                }
            } else {
                cell.frame = frame
            }
            if animated, newSet.contains(ObjectIdentifier(cell)) {
                cell.alphaValue = 0
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.2
                    cell.animator().alphaValue = 1
                }
            }
        }
        updateDropIndicator()
    }

    // MARK: Selection

    var selectedRows: [RowID] {
        selection.ordered(in: rows)
    }

    func select(_ rows: Set<RowID>) {
        selection.set(rows, order: self.rows)
        refreshSelection()
    }

    func selectAllRows() {
        selection.selectAll(rows)
        refreshSelection()
    }

    private func refreshSelection() {
        for (row, cell) in cells {
            cell.isSelected = selection.contains(row)
        }
        delegate?.listViewSelectionDidChange(self)
    }

    private func modifier(for event: NSEvent) -> SelectionModel.Modifier {
        if event.modifierFlags.contains(.shift) { return .extend }
        if event.modifierFlags.contains(.command) { return .toggle }
        return .none
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        dragStarted = false
        selectOnMouseUp = nil
        toggleOnMouseUp = nil
        mouseDownPoint = point
        guard let index = layoutModel.rowIndex(at: point, frames: frames) else {
            mouseDownRow = nil
            selection.clear()
            refreshSelection()
            return
        }
        let row = rows[index]
        mouseDownRow = row
        let modifier = modifier(for: event)
        Log.shelf.debug("mouse down on row \(index) (clicks \(event.clickCount))")

        if event.clickCount == 2, modifier == .none {
            if event.modifierFlags.contains(.option) {
                selectAllRows()
            } else {
                delegate?.listView(self, open: row)
            }
            return
        }
        if modifier == .none, selection.contains(row) {
            selectOnMouseUp = row // keep a multi-selection intact in case this becomes a drag
        } else if modifier == .toggle, selection.contains(row) {
            toggleOnMouseUp = row // ⌘-drag of a selection (⌘ = force move) keeps all selected rows
        } else {
            selection.click(row, modifier: modifier, order: rows)
            refreshSelection()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let row = mouseDownRow, !dragStarted else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - mouseDownPoint.x, point.y - mouseDownPoint.y) >= 3 else { return }
        dragStarted = true
        selectOnMouseUp = nil
        toggleOnMouseUp = nil
        Log.shelf.debug("starting drag of \(self.selectedRows.count) row(s)")
        if !selection.contains(row) {
            selection.click(row, modifier: .none, order: rows)
            refreshSelection()
        }
        delegate?.listView(self, beginDragOf: selectedRows, event: event)
    }

    override func mouseUp(with event: NSEvent) {
        if let row = selectOnMouseUp, !dragStarted {
            selection.click(row, modifier: .none, order: rows)
            refreshSelection()
        }
        if let row = toggleOnMouseUp, !dragStarted {
            selection.click(row, modifier: .toggle, order: rows)
            refreshSelection()
        }
        selectOnMouseUp = nil
        toggleOnMouseUp = nil
        mouseDownRow = nil
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        if let index = layoutModel.rowIndex(at: point, frames: frames) {
            let row = rows[index]
            if !selection.contains(row) {
                selection.click(row, modifier: .none, order: rows)
                refreshSelection()
            }
        } else if !selection.isEmpty {
            selection.clear() // empty space: offer the shelf menu, not actions on an off-screen selection
            refreshSelection()
        }
        return delegate?.listView(self, menuFor: selectedRows)
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        let extend = event.modifierFlags.contains(.shift)
        switch Int(event.keyCode) {
        case 49: delegate?.listViewQuickLook(self)
        case 51, 117: delegate?.listViewDelete(self)
        case 53: delegate?.listViewCancel(self)
        case 36, 76: if let row = selectedRows.first { delegate?.listView(self, open: row) }
        case 125 where layoutModel.isVertical, 124 where !layoutModel.isVertical: moveSelection(by: 1, extend: extend)
        case 126 where layoutModel.isVertical, 123 where !layoutModel.isVertical: moveSelection(by: -1, extend: extend)
        default: super.keyDown(with: event)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command,
              window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        switch event.charactersIgnoringModifiers {
        case "a": selectAllRows()
        case "c": delegate?.listViewCopy(self)
        case "v": delegate?.listViewPaste(self)
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

    override func cancelOperation(_ sender: Any?) {
        delegate?.listViewCancel(self)
    }

    func moveSelection(by delta: Int, extend: Bool) {
        selection.move(by: delta, extend: extend, order: rows)
        refreshSelection()
        if let cursor = selection.cursor, let frame = frame(for: cursor) {
            scrollToVisible(frame)
        }
    }

    // MARK: Drop indicator

    func dropTarget(at point: NSPoint, allowOnto: Bool) -> ShelfLayout.DropTarget {
        layoutModel.dropTarget(at: point, frames: frames, allowOnto: allowOnto)
    }

    private func updateDropIndicator() {
        for (index, row) in rows.enumerated() {
            cells[row]?.isDropTarget = dropTarget == .onto(index)
        }
        guard case let .between(index) = dropTarget, !rows.isEmpty else {
            insertionIndicator.isHidden = true
            return
        }
        let padding = layoutModel.metrics.padding
        let position: CGFloat = if index < frames.count {
            layoutModel.isVertical ? frames[index].minY : frames[index].minX
        } else {
            layoutModel.isVertical ? (frames.last?.maxY ?? padding) : (frames.last?.maxX ?? padding)
        }
        insertionIndicator.frame = layoutModel.isVertical
            ? NSRect(x: padding + 4, y: position - 1.5, width: bounds.width - 2 * padding - 8, height: 3)
            : NSRect(x: position - 1.5, y: padding + 4, width: 3, height: bounds.height - 2 * padding - 8)
        insertionIndicator.isHidden = false
    }
}
