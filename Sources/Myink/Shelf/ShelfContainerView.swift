import AppKit
import MyinkCore

protocol ShelfContainerDelegate: AnyObject {
    func containerDraggingEntered(_ info: any NSDraggingInfo) -> NSDragOperation
    func containerDraggingUpdated(_ info: any NSDraggingInfo) -> NSDragOperation
    func containerDraggingExited()
    func containerPerformDrop(_ info: any NSDraggingInfo) -> Bool
    func containerPointerEntered()
    func containerPointerExited()
}

/// The shelf's content: header, scrolling list and empty-state label. It is the drop target for the
/// whole panel and reports pointer enter/exit (tracking areas don't fire during drags, so drags
/// report through the dragging methods instead).
final class ShelfContainerView: NSView {
    weak var delegate: ShelfContainerDelegate?
    let header = ShelfHeaderView()
    let scrollView = NSScrollView()
    let emptyLabel = NSTextField(wrappingLabelWithString: "Drop anything here")
    var isVertical = true {
        didSet { if isVertical != oldValue { needsLayout = true } }
    }

    var headerLength: CGFloat = 32 {
        didSet { needsLayout = true }
    }

    var isHighlighted = false {
        didSet { if isHighlighted != oldValue { updateHighlight() } }
    }

    init(list: ShelfListView) {
        super.init(frame: .zero)
        wantsLayer = true
        scrollView.documentView = list
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.automaticallyAdjustsContentInsets = false
        emptyLabel.alignment = .center
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.font = .systemFont(ofSize: 12, weight: .medium)
        addSubview(scrollView)
        addSubview(header)
        addSubview(emptyLabel)
        registerForDraggedTypes(TypeCatalog.acceptedDragTypes.map { NSPasteboard.PasteboardType($0) })
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layout() {
        super.layout()
        header.isVertical = isVertical
        scrollView.hasVerticalScroller = isVertical
        scrollView.hasHorizontalScroller = !isVertical
        if isVertical {
            header.frame = NSRect(x: 0, y: bounds.height - headerLength, width: bounds.width, height: headerLength)
            scrollView.frame = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height - headerLength)
        } else {
            header.frame = NSRect(x: 0, y: 0, width: headerLength, height: bounds.height)
            scrollView.frame = NSRect(x: headerLength, y: 0, width: bounds.width - headerLength, height: bounds.height)
        }
        emptyLabel.preferredMaxLayoutWidth = scrollView.frame.width - 16
        let labelSize = emptyLabel.intrinsicContentSize
        emptyLabel.frame = NSRect(
            x: scrollView.frame.midX - min(labelSize.width, scrollView.frame.width - 16) / 2,
            y: scrollView.frame.midY - labelSize.height / 2,
            width: min(labelSize.width, scrollView.frame.width - 16),
            height: labelSize.height
        )
        (scrollView.documentView as? ShelfListView)?.relayout(animated: false)
    }

    private func updateHighlight() {
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        layer?.borderWidth = isHighlighted ? 2 : 0
        layer?.cornerRadius = 16
    }

    // MARK: Pointer tracking

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        delegate?.containerPointerEntered()
    }

    override func mouseExited(with event: NSEvent) {
        delegate?.containerPointerExited()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    // MARK: Dragging destination

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        delegate?.containerDraggingEntered(sender) ?? []
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        delegate?.containerDraggingUpdated(sender) ?? []
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        delegate?.containerDraggingExited()
        delegate?.containerPointerExited() // tracking areas don't report exits during drags
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        true
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        delegate?.containerPerformDrop(sender) ?? false
    }

    override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {
        delegate?.containerDraggingExited()
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        isHighlighted = false
    }
}

/// Item count plus Clear and the actions menu.
final class ShelfHeaderView: NSView {
    var onClear: ((_ includingLocked: Bool) -> Void)?
    var onMenu: ((NSView) -> Void)?
    var isVertical = true {
        didSet { needsLayout = true }
    }

    private let countLabel = NSTextField(labelWithString: "")
    private let clearButton = FirstMouseButton()
    private let menuButton = FirstMouseButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        countLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        countLabel.textColor = .secondaryLabelColor
        countLabel.lineBreakMode = .byTruncatingTail
        configure(clearButton, symbol: "xmark.bin", tip: "Clear the shelf (⌥: including locked items)", action: #selector(clearClicked))
        configure(menuButton, symbol: "ellipsis.circle", tip: "More", action: #selector(menuClicked))
        [countLabel, clearButton, menuButton].forEach(addSubview)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func configure(_ button: NSButton, symbol: String, tip: String, action: Selector) {
        button.isBordered = false
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = tip
        button.target = self
        button.action = action
    }

    func set(itemCount: Int) {
        countLabel.stringValue = itemCount == 0 ? "" : "\(itemCount)"
        countLabel.toolTip = itemCount == 1 ? "1 item" : "\(itemCount) items"
        clearButton.isEnabled = itemCount > 0
    }

    override func layout() {
        super.layout()
        let button: CGFloat = 20
        if isVertical {
            let y = (bounds.height - button) / 2
            menuButton.frame = NSRect(x: bounds.width - button - 8, y: y, width: button, height: button)
            clearButton.frame = NSRect(x: menuButton.frame.minX - button - 2, y: y, width: button, height: button)
            countLabel.frame = NSRect(x: 12, y: y + 2, width: clearButton.frame.minX - 16, height: 16)
            countLabel.alignment = .left
        } else {
            let x = (bounds.width - button) / 2
            countLabel.frame = NSRect(x: 2, y: bounds.height - 24, width: bounds.width - 4, height: 16)
            countLabel.alignment = .center
            clearButton.frame = NSRect(x: x, y: 30, width: button, height: button)
            menuButton.frame = NSRect(x: x, y: 8, width: button, height: button)
        }
    }

    @objc private func clearClicked() {
        onClear?(NSEvent.modifierFlags.contains(.option))
    }

    @objc private func menuClicked() {
        onMenu?(menuButton)
    }
}
