import AppKit
import MyinkCore

/// One tile on the shelf: thumbnail (a fan for stacks), name, and hover controls.
final class ShelfCellView: NSView {
    struct Model: Equatable {
        enum Status: Equatable {
            case normal, pending, failed, missing, inTrash, offline
        }

        var title: String
        var images: [NSImage]
        /// Items in the entry (more than one for a stack).
        var itemCount: Int
        var isLocked: Bool
        var isChild: Bool
        var isExpanded: Bool
        var status: Status
        var toolTip: String?
    }

    var onToggleLock: ((_ allEntries: Bool) -> Void)?
    var onRemove: (() -> Void)?
    var onToggleExpand: (() -> Void)?

    var isSelected = false {
        didSet { if isSelected != oldValue { updateAppearance() } }
    }

    var isDropTarget = false {
        didSet { if isDropTarget != oldValue { updateAppearance() } }
    }

    private(set) var model: Model?
    var thumbnailSize: CGFloat = 56 {
        didSet { needsLayout = true }
    }

    private let thumbnail = StackThumbnailView()
    private let titleField = NSTextField(wrappingLabelWithString: "")
    private let badgeButton = FirstMouseButton()
    private let lockButton = FirstMouseButton()
    private let removeButton = FirstMouseButton()
    private let spinner = NSProgressIndicator()
    private let statusIcon = NSImageView()
    private var isHovered = false {
        didSet { if isHovered != oldValue { updateControls() } }
    }

    override var isFlipped: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous

        titleField.font = .systemFont(ofSize: 11)
        titleField.alignment = .center
        titleField.maximumNumberOfLines = 2
        titleField.lineBreakMode = .byWordWrapping
        titleField.cell?.truncatesLastVisibleLine = true
        titleField.textColor = .labelColor

        badgeButton.bezelStyle = .badge
        badgeButton.isBordered = true
        badgeButton.font = .systemFont(ofSize: 10, weight: .semibold)
        badgeButton.target = self
        badgeButton.action = #selector(badgeClicked)
        badgeButton.toolTip = "Show or hide the items in this stack"

        configure(
            lockButton,
            symbol: "lock.fill",
            action: #selector(lockClicked(_:)),
            tip: "Locked items stay on the shelf after you drag them out (⌥-click: all items)"
        )
        configure(removeButton, symbol: "xmark.circle.fill", action: #selector(removeClicked), tip: "Remove from the shelf")

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false

        statusIcon.imageScaling = .scaleProportionallyUpOrDown

        for view in [thumbnail, titleField, statusIcon, spinner, badgeButton, lockButton, removeButton] {
            addSubview(view)
        }
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func configure(_ button: NSButton, symbol: String, action: Selector, tip: String) {
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
        button.contentTintColor = .secondaryLabelColor
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        button.target = self
        button.action = action
        button.toolTip = tip
    }

    func apply(_ model: Model) {
        guard model != self.model else { return }
        self.model = model
        thumbnail.images = model.images
        thumbnail.alphaValue = [.missing, .offline, .failed].contains(model.status) ? 0.45 : 1
        titleField.stringValue = model.title
        titleField.maximumNumberOfLines = model.isChild ? 1 : 2
        titleField.font = .systemFont(ofSize: model.isChild ? 10 : 11)
        badgeButton.title = "\(model.itemCount)"
        toolTip = model.toolTip ?? model.title
        setAccessibilityLabel(accessibilityDescription(for: model))
        if model.status == .pending { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
        statusIcon.image = statusImage(for: model.status)
        statusIcon.contentTintColor = model.status == .inTrash ? .secondaryLabelColor : .systemOrange
        statusIcon.toolTip = statusTip(for: model.status)
        updateControls()
        needsLayout = true
    }

    /// Replaces the thumbnail images (when a Quick Look thumbnail arrives).
    func updateImages(_ images: [NSImage]) {
        model?.images = images
        thumbnail.images = images
    }

    // MARK: Layout

    override func layout() {
        super.layout()
        let isChild = model?.isChild ?? false
        let size = isChild ? thumbnailSize * 0.62 : thumbnailSize
        let inset: CGFloat = isChild ? 10 : 0
        let top: CGFloat = isChild ? 5 : 7
        thumbnail.frame = NSRect(x: (bounds.width - size) / 2 + inset / 2, y: top, width: size, height: size)
        let titleTop = thumbnail.frame.maxY + 3
        titleField.preferredMaxLayoutWidth = bounds.width - 8 - inset
        titleField.frame = NSRect(x: 4 + inset, y: titleTop, width: bounds.width - 8 - inset, height: max(bounds.height - titleTop - 2, 12))

        let badgeSize = badgeButton.intrinsicContentSize
        badgeButton.frame = NSRect(
            x: min(thumbnail.frame.maxX - badgeSize.width / 2, bounds.width - badgeSize.width - 2),
            y: max(thumbnail.frame.minY - 5, 1),
            width: badgeSize.width,
            height: badgeSize.height
        )
        lockButton.frame = NSRect(x: thumbnail.frame.maxX - 12, y: thumbnail.frame.maxY - 14, width: 18, height: 18)
        removeButton.frame = NSRect(x: 3, y: 3, width: 18, height: 18)
        statusIcon.frame = NSRect(x: thumbnail.frame.minX - 4, y: thumbnail.frame.maxY - 16, width: 18, height: 18)
        spinner.frame = NSRect(x: thumbnail.frame.midX - 8, y: thumbnail.frame.midY - 8, width: 16, height: 16)
    }

    // MARK: Appearance

    private func updateAppearance() {
        if isDropTarget {
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.25).cgColor
            layer?.borderColor = NSColor.controlAccentColor.cgColor
            layer?.borderWidth = 2
        } else {
            layer?.backgroundColor = isSelected ? NSColor.controlAccentColor.withAlphaComponent(0.28).cgColor : NSColor.clear.cgColor
            layer?.borderWidth = 0
        }
    }

    private func updateControls() {
        guard let model else { return }
        let pending = model.status == .pending || model.status == .failed
        badgeButton.isHidden = model.isChild || model.itemCount < 2
        badgeButton.contentTintColor = model.isExpanded ? .controlAccentColor : nil
        removeButton.isHidden = !isHovered || pending
        lockButton.isHidden = model.isChild || pending || !(model.isLocked || isHovered)
        lockButton.image = NSImage(
            systemSymbolName: model.isLocked ? "lock.fill" : "lock.open",
            accessibilityDescription: model.isLocked ? "Unlock" : "Lock"
        )
        lockButton.contentTintColor = model.isLocked ? .controlAccentColor : .secondaryLabelColor
        statusIcon.isHidden = statusIcon.image == nil
    }

    private func statusImage(for status: Model.Status) -> NSImage? {
        let name: String? = switch status {
        case .normal, .pending: nil
        case .failed, .missing: "exclamationmark.triangle.fill"
        case .inTrash: "trash.fill"
        case .offline: "externaldrive.badge.xmark"
        }
        return name.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: statusTip(for: status)) }
    }

    private func statusTip(for status: Model.Status) -> String? {
        switch status {
        case .normal, .pending: nil
        case .failed: "This item couldn't be added."
        case .missing: "The original file can't be found."
        case .inTrash: "The original file is in the Trash."
        case .offline: "The disk holding this file isn't connected."
        }
    }

    private func accessibilityDescription(for model: Model) -> String {
        var parts = [model.title]
        if model.itemCount > 1 { parts.append("stack of \(model.itemCount) items") }
        if model.isLocked { parts.append("locked") }
        if let tip = statusTip(for: model.status) { parts.append(tip) }
        return parts.joined(separator: ", ")
    }

    // MARK: Hover & actions

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    @objc private func badgeClicked() {
        onToggleExpand?()
    }

    @objc private func lockClicked(_ sender: NSButton) {
        onToggleLock?(NSEvent.modifierFlags.contains(.option))
    }

    @objc private func removeClicked() {
        onRemove?()
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        .cell
    }

    override func isAccessibilityElement() -> Bool {
        true
    }
}

/// A button that reacts to the first click even while the shelf isn't key.
final class FirstMouseButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

/// Draws one image, or a fanned pile of up to three for a stack.
final class StackThumbnailView: NSView {
    var images: [NSImage] = [] {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let shown = Array(images.prefix(3))
        guard !shown.isEmpty else { return }
        if shown.count == 1 {
            draw(shown[0], in: bounds, rotation: 0)
            return
        }
        let inner = bounds.insetBy(dx: bounds.width * 0.12, dy: bounds.height * 0.12)
        let angles: [CGFloat] = shown.count == 2 ? [-8, 6] : [-12, 10, 0]
        for (index, image) in shown.reversed().enumerated() {
            let angle = angles[min(index, angles.count - 1)]
            draw(image, in: inner, rotation: angle, shadow: true)
        }
    }

    private func draw(_ image: NSImage, in rect: NSRect, rotation degrees: CGFloat, shadow: Bool = false) {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return }
        let scale = min(rect.width / size.width, rect.height / size.height)
        let drawSize = NSSize(width: size.width * scale, height: size.height * scale)
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: rect.midX, yBy: rect.midY)
        transform.rotate(byDegrees: degrees)
        transform.concat()
        if shadow {
            let shadowStyle = NSShadow()
            shadowStyle.shadowBlurRadius = 3
            shadowStyle.shadowOffset = NSSize(width: 0, height: -1)
            shadowStyle.shadowColor = NSColor.black.withAlphaComponent(0.25)
            shadowStyle.set()
        }
        image.draw(
            in: NSRect(x: -drawSize.width / 2, y: -drawSize.height / 2, width: drawSize.width, height: drawSize.height),
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high.rawValue]
        )
        NSGraphicsContext.restoreGraphicsState()
    }
}
