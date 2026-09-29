import AppKit
import MyinkCore

/// The menu bar icon: left click → `onClick` (toggle the shelf); right-click or ⌃-click → shows
/// `menuProvider()`'s menu; also a drop target for files/text/anything the shelf accepts.
///
/// The drop target is the status bar button's window (registered for the accepted drag types, with
/// this controller as its delegate — `NSWindow` forwards dragging-destination messages to it).
final class StatusItemController: NSObject, NSWindowDelegate, NSDraggingDestination {
    var onClick: (() -> Void)?
    var menuProvider: (() -> NSMenu)?
    /// Validates a drag over the icon (return `[]` to refuse). Default when nil: `.copy` if the
    /// pasteboard has any of `TypeCatalog.acceptedDragTypes`.
    var validateDrop: ((any NSDraggingInfo) -> NSDragOperation)?
    /// Performs the drop; returns success.
    var performDrop: ((any NSDraggingInfo) -> Bool)?

    var isVisible: Bool {
        get { statusItem.isVisible }
        set { statusItem.isVisible = newValue }
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let image = StatusItemController.symbol("tray.and.arrow.down")
    private let hoverImage = StatusItemController.symbol("tray.and.arrow.down.fill")
    /// Last operation returned while the drag was over the icon; `[]` when outside or refused.
    private var lastOperation: NSDragOperation = []
    /// Set once the current drag has been delivered, so `draggingEnded` doesn't deliver it again.
    private var dropHandled = false
    private var flashTask: Task<Void, Never>?

    override init() {
        super.init()
        guard let button = statusItem.button else { return }
        button.image = image
        button.target = self
        button.action = #selector(buttonClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.setAccessibilityLabel("Myink")
        button.toolTip = "Myink"
        if let window = button.window {
            window.registerForDraggedTypes(TypeCatalog.acceptedDragTypes.map { NSPasteboard.PasteboardType($0) })
            window.delegate = self
        } else {
            Log.app.error("Status item button has no window; the icon won't accept drops")
        }
    }

    /// Briefly highlights the icon (e.g. after something was added).
    func flash() {
        guard let button = statusItem.button else { return }
        flashTask?.cancel()
        flashTask = Task { @MainActor [weak button] in
            for highlighted in [true, false, true] {
                button?.highlight(highlighted)
                try? await Task.sleep(for: .milliseconds(120))
                if Task.isCancelled { break }
            }
            button?.highlight(false)
        }
    }

    // MARK: - Clicks

    @objc private func buttonClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if wantsMenu, let menu = menuProvider?() {
            // Attached only for this click so left clicks keep going to `onClick`.
            statusItem.menu = menu
            sender.performClick(nil)
            statusItem.menu = nil
        } else {
            onClick?()
        }
    }

    // MARK: - Drop target

    func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        dropHandled = false
        return update(sender)
    }

    func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        update(sender)
    }

    func draggingExited(_ sender: (any NSDraggingInfo)?) {
        lastOperation = []
        setHovering(false)
    }

    func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        setHovering(false)
        return deliver(sender, via: "performDragOperation")
    }

    /// Fallback for sources that end the session without sending `performDragOperation` (Dock
    /// stacks are known to): deliver the drop if it ended over the icon with an accepted operation.
    func draggingEnded(_ sender: any NSDraggingInfo) {
        defer {
            lastOperation = []
            dropHandled = false
            setHovering(false)
        }
        guard !lastOperation.isEmpty, isOverButton(NSEvent.mouseLocation) else { return }
        _ = deliver(sender, via: "draggingEnded fallback")
    }

    private func deliver(_ sender: any NSDraggingInfo, via path: String) -> Bool {
        guard !dropHandled else { return false }
        dropHandled = true
        let success = performDrop?(sender) ?? false
        Log.drag.info("Status item drop (\(path, privacy: .public)): \(success ? "accepted" : "failed", privacy: .public)")
        return success
    }

    private func update(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let operation = validateDrop?(sender) ?? defaultOperation(sender)
        lastOperation = operation
        setHovering(!operation.isEmpty)
        return operation
    }

    private func defaultOperation(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let types = sender.draggingPasteboard.types?.map(\.rawValue) ?? []
        return TypeCatalog.acceptsDrag(types: types) ? .copy : []
    }

    private func setHovering(_ hovering: Bool) {
        guard let button = statusItem.button else { return }
        let wanted = hovering ? hoverImage : image
        if button.image !== wanted { button.image = wanted }
    }

    private func isOverButton(_ screenPoint: NSPoint) -> Bool {
        guard let button = statusItem.button, let window = button.window else { return false }
        let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
        return frame.insetBy(dx: -1, dy: -1).contains(screenPoint)
    }

    private static func symbol(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Myink")
        image?.isTemplate = true
        return image
    }
}
