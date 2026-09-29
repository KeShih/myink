import CoreGraphics
import Foundation

/// Identifies a row in the shelf list: an entry, or one item of an expanded stack.
public enum RowID: Hashable, Sendable {
    case entry(UUID)
    case child(entry: UUID, item: UUID)

    public var entryID: UUID {
        switch self {
        case let .entry(id), let .child(id, _): id
        }
    }
}

public enum ShelfRows {
    /// Rows for the list: every entry, followed by its items when it's an expanded stack.
    public static func rows(for entries: [ShelfEntry], expanded: Set<UUID>) -> [RowID] {
        var rows: [RowID] = []
        for entry in entries {
            rows.append(.entry(entry.id))
            if entry.isStack, expanded.contains(entry.id) {
                rows += entry.items.map { .child(entry: entry.id, item: $0.id) }
            }
        }
        return rows
    }
}

/// Lays out rows inside the shelf's scrolling list. Coordinates are flipped (origin top-left), as in
/// the list's document view. Vertical shelves stack rows downward, horizontal ones rightward.
public struct ShelfLayout: Sendable, Equatable {
    public enum DropTarget: Sendable, Equatable {
        /// Between rows: insert at this row index (0…count).
        case between(Int)
        /// Onto the middle of a row (merge into that entry).
        case onto(Int)
    }

    public var isVertical: Bool
    public var metrics: ShelfMetrics

    public init(isVertical: Bool, metrics: ShelfMetrics) {
        self.isVertical = isVertical
        self.metrics = metrics
    }

    public func length(of row: RowID) -> CGFloat {
        if case .child = row { return metrics.childCellLength }
        return metrics.cellLength
    }

    public func frames(for rows: [RowID]) -> [CGRect] {
        var offset = metrics.padding
        let cross = metrics.thickness - 2 * metrics.padding
        return rows.map { row in
            let length = length(of: row)
            defer { offset += length }
            return isVertical
                ? CGRect(x: metrics.padding, y: offset, width: cross, height: length)
                : CGRect(x: offset, y: metrics.padding, width: length, height: cross)
        }
    }

    /// Length along the shelf needed to show every row (with padding at both ends).
    public func contentLength(for rows: [RowID]) -> CGFloat {
        rows.reduce(2 * metrics.padding) { $0 + length(of: $1) }
    }

    public func rowIndex(at point: CGPoint, frames: [CGRect]) -> Int? {
        frames.firstIndex { $0.contains(point) }
    }

    /// Where a drop at `point` lands. With `allowOnto`, the middle half of a row targets the row
    /// itself; otherwise the drop goes between rows.
    public func dropTarget(at point: CGPoint, frames: [CGRect], allowOnto: Bool) -> DropTarget {
        for (index, frame) in frames.enumerated() {
            let position = isVertical ? point.y : point.x
            let start = isVertical ? frame.minY : frame.minX
            let length = isVertical ? frame.height : frame.width
            guard position < start + length else { continue }
            let fraction = (position - start) / max(length, 1)
            if allowOnto, fraction >= 0.25, fraction <= 0.75 { return .onto(index) }
            return .between(fraction < 0.5 ? index : index + 1)
        }
        return .between(frames.count)
    }
}
