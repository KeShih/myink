import CoreGraphics
import Foundation

/// When a detected drag should reveal the shelf.
public enum TriggerMode: String, Codable, CaseIterable, Sendable {
    /// As soon as a drag gets going (Yoink's default).
    case onDragStart
    /// Only when the drag approaches the shelf's screen edge.
    case nearEdge
    /// When the pointer is shaken during the drag.
    case shake
    /// Never automatically; use the hotkey or menu bar icon.
    case never
}

/// Whether a detected drag is one the shelf should react to at all.
public enum DragAcceptance {
    public static func accepts(
        types: [String],
        sourceBundleID: String?,
        fnHeld: Bool,
        preferences: Preferences,
        ownBundleID: String
    ) -> Bool {
        guard preferences.autoShowEnabled, preferences.triggerMode != .never else { return false }
        if fnHeld, preferences.fnSuppressesShelf { return false }
        if let sourceBundleID {
            if sourceBundleID == ownBundleID || preferences.excludedBundleIDs.contains(sourceBundleID) { return false }
        }
        return TypeCatalog.acceptsDrag(types: types)
    }
}

/// Watches pointer samples during one drag and decides when (and where) to reveal the shelf.
public struct DragTriggerEvaluator: Sendable {
    public static let minimumDistance: CGFloat = 6
    public static let minimumDelay: TimeInterval = 0.08
    public static let edgeThreshold: CGFloat = 24
    /// Larger at the top: dragging a file into the top edge can open Mission Control on macOS 27,
    /// so reveal before the pointer gets there.
    public static let topEdgeThreshold: CGFloat = 72
    /// Edges shared with another display need a short dwell, or crossing displays would trigger.
    public static let interiorEdgeDwell: TimeInterval = 0.25

    public let mode: TriggerMode
    public let edge: ScreenEdge
    public let nearPointer: Bool
    private let start: CGPoint
    private let startTime: TimeInterval
    private var nearSince: TimeInterval?
    private var shake = ShakeDetector()
    public private(set) var hasRevealed = false

    public init(mode: TriggerMode, edge: ScreenEdge, nearPointer: Bool, start: CGPoint, startTime: TimeInterval) {
        self.mode = mode
        self.edge = edge
        self.nearPointer = nearPointer
        self.start = start
        self.startTime = startTime
    }

    /// Feeds one pointer sample. Returns a placement the first time the shelf should appear.
    public mutating func sample(point: CGPoint, time: TimeInterval, screenFrame: CGRect, isOuterEdge: Bool) -> VisibilityMachine.Placement? {
        guard !hasRevealed else { return nil }
        let reveal: Bool
        switch mode {
        case .never:
            reveal = false
        case .onDragStart:
            let moved = hypot(point.x - start.x, point.y - start.y)
            reveal = moved >= Self.minimumDistance && time - startTime >= Self.minimumDelay
        case .nearEdge:
            let threshold = edge == .top ? Self.topEdgeThreshold : Self.edgeThreshold
            if EdgeGeometry.isNear(point, edge: edge, screenFrame: screenFrame, threshold: threshold) {
                let since = nearSince ?? time
                nearSince = since
                reveal = isOuterEdge || time - since >= Self.interiorEdgeDwell
            } else {
                nearSince = nil
                reveal = false
            }
        case .shake:
            reveal = shake.add(point, at: time)
        }
        guard reveal else { return nil }
        hasRevealed = true
        return nearPointer && mode != .nearEdge ? .nearPointer(point) : .edge
    }
}

/// Detects a quick side-to-side shake of the pointer.
public struct ShakeDetector: Sendable {
    public var requiredReversals = 4
    public var minimumTravel: CGFloat = 20
    public var window: TimeInterval = 0.8

    private var lastX: CGFloat?
    private var pivotX: CGFloat = 0
    private var direction = 0
    private var reversals: [TimeInterval] = []

    public init() {}

    /// Returns true when the latest sample completes a shake.
    public mutating func add(_ point: CGPoint, at time: TimeInterval) -> Bool {
        guard let last = lastX else {
            lastX = point.x
            pivotX = point.x
            return false
        }
        let dx = point.x - last
        lastX = point.x
        guard abs(dx) >= 1 else { return false }
        let newDirection = dx > 0 ? 1 : -1
        if direction == 0 {
            direction = newDirection
        } else if newDirection != direction {
            if abs(last - pivotX) >= minimumTravel { reversals.append(time) }
            pivotX = last
            direction = newDirection
        }
        reversals.removeAll { time - $0 > window }
        if reversals.count >= requiredReversals {
            reversals.removeAll()
            return true
        }
        return false
    }
}

/// Tells a tap of the hotkey from a long press (hold ≥ `threshold`), with an injectable clock.
public struct LongPressDetector: Sendable {
    public enum Output: Sendable, Equatable {
        case tap, longPress
    }

    public var threshold: TimeInterval
    private var pressedAt: TimeInterval?
    private var firedLongPress = false

    public init(threshold: TimeInterval = 1.0) {
        self.threshold = threshold
    }

    public var isPressed: Bool { pressedAt != nil }

    /// Records a press. Returns the time at which `deadlineReached` should be called, or nil for an
    /// auto-repeat while already pressed.
    public mutating func press(at time: TimeInterval) -> TimeInterval? {
        guard pressedAt == nil else { return nil }
        pressedAt = time
        firedLongPress = false
        return time + threshold
    }

    public mutating func deadlineReached(at time: TimeInterval) -> Output? {
        guard let pressedAt, !firedLongPress, time - pressedAt >= threshold - 0.001 else { return nil }
        firedLongPress = true
        return .longPress
    }

    public mutating func release(at time: TimeInterval) -> Output? {
        defer {
            pressedAt = nil
            firedLongPress = false
        }
        guard let pressedAt, !firedLongPress else { return nil }
        return time - pressedAt >= threshold ? .longPress : .tap
    }
}
