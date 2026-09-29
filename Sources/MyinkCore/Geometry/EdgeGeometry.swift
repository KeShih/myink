import CoreGraphics

public enum ScreenEdge: String, Codable, CaseIterable, Sendable {
    case left, right, top, bottom

    /// Left/right shelves run vertically; top/bottom shelves run horizontally.
    public var isVertical: Bool { self == .left || self == .right }
}

public enum EdgeAlignment: String, Codable, CaseIterable, Sendable {
    /// Top of a vertical shelf, left end of a horizontal one.
    case start
    case center
    /// Bottom of a vertical shelf, right end of a horizontal one.
    case end
}

public enum ShelfSize: String, Codable, CaseIterable, Sendable {
    case small, medium, large
}

/// Dimensions of the shelf for a size setting. "Length" runs along the edge, "thickness" across it.
public struct ShelfMetrics: Sendable, Equatable {
    public var thickness: CGFloat
    public var cellLength: CGFloat
    public var childCellLength: CGFloat
    public var thumbnailSize: CGFloat
    public var headerLength: CGFloat
    public var padding: CGFloat

    public static func metrics(for size: ShelfSize) -> ShelfMetrics {
        switch size {
        case .small: ShelfMetrics(thickness: 92, cellLength: 84, childCellLength: 64, thumbnailSize: 44, headerLength: 30, padding: 6)
        case .medium: ShelfMetrics(thickness: 112, cellLength: 102, childCellLength: 76, thumbnailSize: 56, headerLength: 32, padding: 8)
        case .large: ShelfMetrics(thickness: 136, cellLength: 126, childCellLength: 92, thumbnailSize: 74, headerLength: 34, padding: 8)
        }
    }
}

/// Pure geometry for placing the shelf, its edge tab and the near-pointer popover.
/// All rects are AppKit global coordinates (origin bottom-left of the primary display).
public enum EdgeGeometry {
    /// Gap between the shelf and the screen edge.
    public static let margin: CGFloat = 8
    /// A non-full-length shelf never covers more of its edge than this.
    public static let maximumEdgeFraction: CGFloat = 0.6
    public static let tabSize = CGSize(width: 6, height: 72)

    /// Index of the screen containing `point`, else the nearest one.
    public static func screenIndex(containing point: CGPoint, screens: [CGRect]) -> Int? {
        if let index = screens.firstIndex(where: { contains($0, point) }) { return index }
        return screens.indices.min { distance(point, screens[$0]) < distance(point, screens[$1]) }
    }

    /// The shelf's frame along `edge` of a screen's visible frame. `contentLength` is the length the
    /// content wants (header + rows); it's clamped to the edge (or fills it when `fullLength`).
    public static func shelfFrame(
        edge: ScreenEdge,
        alignment: EdgeAlignment,
        visibleFrame: CGRect,
        contentLength: CGFloat,
        thickness: CGFloat,
        fullLength: Bool
    ) -> CGRect {
        let edgeLength = edge.isVertical ? visibleFrame.height : visibleFrame.width
        let available = max(edgeLength - 2 * margin, 0)
        let length = fullLength ? available : min(max(contentLength, thickness), available * maximumEdgeFraction)

        let alongStart: CGFloat
        if edge.isVertical {
            switch alignment {
            case .start: alongStart = visibleFrame.maxY - margin - length
            case .center: alongStart = visibleFrame.midY - length / 2
            case .end: alongStart = visibleFrame.minY + margin
            }
        } else {
            switch alignment {
            case .start: alongStart = visibleFrame.minX + margin
            case .center: alongStart = visibleFrame.midX - length / 2
            case .end: alongStart = visibleFrame.maxX - margin - length
            }
        }

        switch edge {
        case .left: return CGRect(x: visibleFrame.minX + margin, y: alongStart, width: thickness, height: length)
        case .right: return CGRect(x: visibleFrame.maxX - margin - thickness, y: alongStart, width: thickness, height: length)
        case .top: return CGRect(x: alongStart, y: visibleFrame.maxY - margin - thickness, width: length, height: thickness)
        case .bottom: return CGRect(x: alongStart, y: visibleFrame.minY + margin, width: length, height: thickness)
        }
    }

    /// Where a show/hide animation starts (or ends): the frame nudged away from the screen's center.
    public static func slideFrame(from frame: CGRect, edge: ScreenEdge, distance: CGFloat) -> CGRect {
        switch edge {
        case .left: frame.offsetBy(dx: -distance, dy: 0)
        case .right: frame.offsetBy(dx: distance, dy: 0)
        case .top: frame.offsetBy(dx: 0, dy: distance)
        case .bottom: frame.offsetBy(dx: 0, dy: -distance)
        }
    }

    /// A thin pill flush against the edge, centered on where the shelf would be.
    public static func tabFrame(edge: ScreenEdge, shelfFrame: CGRect, visibleFrame: CGRect) -> CGRect {
        let size = edge.isVertical ? tabSize : CGSize(width: tabSize.height, height: tabSize.width)
        switch edge {
        case .left: return CGRect(x: visibleFrame.minX, y: shelfFrame.midY - size.height / 2, width: size.width, height: size.height)
        case .right: return CGRect(x: visibleFrame.maxX - size.width, y: shelfFrame.midY - size.height / 2, width: size.width, height: size.height)
        case .top: return CGRect(x: shelfFrame.midX - size.width / 2, y: visibleFrame.maxY - size.height, width: size.width, height: size.height)
        case .bottom: return CGRect(x: shelfFrame.midX - size.width / 2, y: visibleFrame.minY, width: size.width, height: size.height)
        }
    }

    /// A compact frame beside the pointer: to its right (or left if there's no room), vertically
    /// centered on it, clamped to the visible frame.
    public static func nearPointerFrame(pointer: CGPoint, size: CGSize, visibleFrame: CGRect, offset: CGFloat = 28) -> CGRect {
        var x = pointer.x + offset
        if x + size.width > visibleFrame.maxX - margin {
            x = pointer.x - offset - size.width
        }
        let y = pointer.y - size.height / 2
        return clamp(CGRect(x: x, y: y, width: size.width, height: size.height), to: visibleFrame.insetBy(dx: margin, dy: margin))
    }

    /// Whether `point` is within `threshold` of `edge` of the screen frame.
    public static func isNear(_ point: CGPoint, edge: ScreenEdge, screenFrame: CGRect, threshold: CGFloat) -> Bool {
        guard contains(screenFrame.insetBy(dx: -1, dy: -1), point) else { return false }
        switch edge {
        case .left: return point.x - screenFrame.minX <= threshold
        case .right: return screenFrame.maxX - point.x <= threshold
        case .top: return screenFrame.maxY - point.y <= threshold
        case .bottom: return point.y - screenFrame.minY <= threshold
        }
    }

    /// False when another display adjoins this edge (the pointer can cross it).
    public static func isOuterEdge(_ edge: ScreenEdge, of screen: CGRect, allScreens: [CGRect]) -> Bool {
        let tolerance: CGFloat = 2
        for other in allScreens where other != screen {
            switch edge {
            case .left:
                if abs(other.maxX - screen.minX) <= tolerance, overlaps(other.minY ... other.maxY, screen.minY ... screen.maxY) { return false }
            case .right:
                if abs(other.minX - screen.maxX) <= tolerance, overlaps(other.minY ... other.maxY, screen.minY ... screen.maxY) { return false }
            case .top:
                if abs(other.minY - screen.maxY) <= tolerance, overlaps(other.minX ... other.maxX, screen.minX ... screen.maxX) { return false }
            case .bottom:
                if abs(other.maxY - screen.minY) <= tolerance, overlaps(other.minX ... other.maxX, screen.minX ... screen.maxX) { return false }
            }
        }
        return true
    }

    public static func clamp(_ rect: CGRect, to bounds: CGRect) -> CGRect {
        var result = rect
        if result.width > bounds.width { result.size.width = bounds.width }
        if result.height > bounds.height { result.size.height = bounds.height }
        result.origin.x = min(max(result.minX, bounds.minX), bounds.maxX - result.width)
        result.origin.y = min(max(result.minY, bounds.minY), bounds.maxY - result.height)
        return result
    }

    /// Half-open containment like `NSMouseInRect` for unflipped coordinates (max edge excluded).
    static func contains(_ rect: CGRect, _ point: CGPoint) -> Bool {
        point.x >= rect.minX && point.x < rect.maxX && point.y >= rect.minY && point.y < rect.maxY
    }

    static func distance(_ point: CGPoint, _ rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }

    private static func overlaps(_ first: ClosedRange<CGFloat>, _ second: ClosedRange<CGFloat>) -> Bool {
        first.lowerBound < second.upperBound && second.lowerBound < first.upperBound
    }
}
