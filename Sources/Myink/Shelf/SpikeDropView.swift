import AppKit

/// M0 spike: a plain drop target that logs what arrives, to validate that a non-activating panel
/// receives drags from other apps without stealing focus. Replaced by the real shelf in M1.
final class SpikeDropView: NSView {
    var onDrop: (() -> Void)?
    private var highlighted = false {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let promiseTypes: [NSPasteboard.PasteboardType] = NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
        let types: [NSPasteboard.PasteboardType] = [.fileURL, .URL, .string, .rtf, .tiff, .png]
        registerForDraggedTypes(types + promiseTypes)
        wantsLayer = true
        layer?.cornerRadius = 14
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func draw(_ dirtyRect: NSRect) {
        (highlighted ? NSColor.controlAccentColor.withAlphaComponent(0.5) : NSColor.windowBackgroundColor.withAlphaComponent(0.85))
            .setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 14, yRadius: 14).fill()
        let text = "Drop here" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attributes)
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        highlighted = true
        Log.shelf.debug("""
        spike: dragging entered; frontmost=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?", privacy: .public) \
        myinkActive=\(NSApp.isActive) sourceMask=\(sender.draggingSourceOperationMask.rawValue)
        """)
        return sender.draggingSourceOperationMask.contains(.copy) ? .copy : .generic
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        highlighted = false
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        highlighted = false
        let pasteboard = sender.draggingPasteboard
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        let types = pasteboard.pasteboardItems?.first?.types.map(\.rawValue) ?? []
        Log.shelf.info("""
        spike: drop of \(pasteboard.pasteboardItems?.count ?? 0) item(s); files=\(urls.map(\.path), privacy: .public) \
        firstItemTypes=\(types, privacy: .public) myinkActive=\(NSApp.isActive)
        """)
        onDrop?()
        return true
    }
}
