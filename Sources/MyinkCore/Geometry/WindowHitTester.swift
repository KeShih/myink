import CoreGraphics
import Foundation

/// Finds which app owns the window under a point, using the window list that
/// `CGWindowListCopyWindowInfo` returns front-to-back. Owner PID, bounds, layer and alpha are
/// available without Screen Recording permission.
public enum WindowHitTester {
    public struct Window: Equatable, Sendable {
        public var ownerPID: Int32
        /// Bounds in CoreGraphics global coordinates (origin top-left of the primary display).
        public var bounds: CGRect
        public var layer: Int
        public var alpha: Double

        public init(ownerPID: Int32, bounds: CGRect, layer: Int, alpha: Double) {
            self.ownerPID = ownerPID
            self.bounds = bounds
            self.layer = layer
            self.alpha = alpha
        }

        /// Builds a window from one `CGWindowListCopyWindowInfo` dictionary.
        public init?(windowInfo info: [String: Any]) {
            guard let pid = info["kCGWindowOwnerPID"] as? Int32 ?? (info["kCGWindowOwnerPID"] as? Int).map(Int32.init),
                  let boundsDict = info["kCGWindowBounds"] as? [String: Any],
                  let x = Self.number(boundsDict["X"]), let y = Self.number(boundsDict["Y"]),
                  let width = Self.number(boundsDict["Width"]), let height = Self.number(boundsDict["Height"])
            else { return nil }
            ownerPID = pid
            bounds = CGRect(x: x, y: y, width: width, height: height)
            layer = (info["kCGWindowLayer"] as? Int) ?? 0
            alpha = Self.number(info["kCGWindowAlpha"]) ?? 1
        }

        private static func number(_ value: Any?) -> Double? {
            switch value {
            case let double as Double: double
            case let int as Int: Double(int)
            case let float as CGFloat: Double(float)
            case let number as NSNumber: number.doubleValue
            default: nil
            }
        }
    }

    /// Layers above this are overlays (cursor, screen savers, shields, capture UIs), not drag sources.
    /// The menu bar sits at 24–25 and the Dock at 20, both of which can legitimately start drags.
    public static let maximumSourceLayer = 25

    /// Returns the owner of the frontmost plausible window containing `point`
    /// (CoreGraphics coordinates), ignoring `excludingPID` (Myink itself).
    ///
    /// Raised windows (layer > 0) that cover the whole display are skipped: the Dock keeps a
    /// transparent full-screen window at layer 20, and screenshot tools keep similar overlays.
    public static func ownerPID(at point: CGPoint, windows: [Window], excludingPID: Int32, screenBounds: CGRect? = nil) -> Int32? {
        for window in windows where window.ownerPID != excludingPID {
            guard window.layer <= maximumSourceLayer, window.alpha > 0.05, window.bounds.contains(point) else { continue }
            if window.layer > 0, let screenBounds, covers(window.bounds, screenBounds) { continue }
            return window.ownerPID
        }
        return nil
    }

    private static func covers(_ bounds: CGRect, _ screen: CGRect) -> Bool {
        let overlap = bounds.intersection(screen)
        guard !overlap.isNull, screen.width > 0, screen.height > 0 else { return false }
        return overlap.width >= screen.width * 0.95 && overlap.height >= screen.height * 0.95
    }

    /// Converts an AppKit global point (origin bottom-left of the primary display) into
    /// CoreGraphics global coordinates (origin top-left of the primary display).
    public static func cgPoint(fromAppKit point: CGPoint, primaryScreenHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenHeight - point.y)
    }

    /// Converts an AppKit global rect into CoreGraphics global coordinates.
    public static func cgRect(fromAppKit rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}
