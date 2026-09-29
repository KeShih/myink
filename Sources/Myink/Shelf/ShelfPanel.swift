import AppKit

/// The floating shelf window.
///
/// A borderless, non-activating panel: it floats above normal windows on every Space and over
/// full-screen apps, receives drags without activating Myink, and can become key (for Quick Look
/// and keyboard navigation) while another app stays frontmost.
class ShelfPanel: NSPanel {
    init(contentRect: NSRect = NSRect(x: 0, y: 0, width: 120, height: 320)) {
        // `.nonactivatingPanel` must be part of the style mask at init; adding it later leaves the
        // WindowServer's activation tag out of sync.
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true // resets `level`, so set the level afterwards
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isReleasedWhenClosed = false
        isMovable = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none
        isExcludedFromWindowsMenu = true
    }

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    /// Myink positions the panel itself (including partially off-screen during slide animations).
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
