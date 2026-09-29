import AppKit
import MyinkCore

/// Identifies the app a drag started in: the owner of the frontmost window under the mouse-down
/// point (more accurate than "frontmost app" for Desktop, Dock and click-through drags).
struct SourceAppResolver {
    struct Source: Equatable {
        var pid: pid_t
        var bundleIdentifier: String?
    }

    func resolve(atAppKitPoint point: CGPoint) -> Source? {
        if let primary = NSScreen.screens.first,
           let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] {
            let windows = info.compactMap(WindowHitTester.Window.init(windowInfo:))
            let primaryHeight = primary.frame.height
            let cgPoint = WindowHitTester.cgPoint(fromAppKit: point, primaryScreenHeight: primaryHeight)
            let screenBounds = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
                .map { WindowHitTester.cgRect(fromAppKit: $0.frame, primaryScreenHeight: primaryHeight) }
            if let pid = WindowHitTester.ownerPID(at: cgPoint, windows: windows, excludingPID: getpid(), screenBounds: screenBounds) {
                return Source(pid: pid, bundleIdentifier: NSRunningApplication(processIdentifier: pid)?.bundleIdentifier)
            }
        }
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return nil }
        return Source(pid: frontmost.processIdentifier, bundleIdentifier: frontmost.bundleIdentifier)
    }
}
