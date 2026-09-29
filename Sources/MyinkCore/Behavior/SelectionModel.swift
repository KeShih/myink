import Foundation

/// Finder-style selection for the shelf list: click, ⌘-click to toggle, ⇧-click/arrow to extend
/// from the anchor, ⌘A.
public struct SelectionModel: Sendable, Equatable {
    public enum Modifier: Sendable {
        case none
        /// ⇧: select the range from the anchor.
        case extend
        /// ⌘: add or remove one row.
        case toggle
    }

    public private(set) var selected: Set<RowID> = []
    public private(set) var anchor: RowID?
    /// The row keyboard navigation moves from.
    public private(set) var cursor: RowID?

    public init() {}

    public var isEmpty: Bool {
        selected.isEmpty
    }

    public func contains(_ row: RowID) -> Bool {
        selected.contains(row)
    }

    /// Selected rows in list order.
    public func ordered(in order: [RowID]) -> [RowID] {
        order.filter(selected.contains)
    }

    public mutating func click(_ row: RowID, modifier: Modifier, order: [RowID]) {
        switch modifier {
        case .none:
            selected = [row]
            anchor = row
        case .toggle:
            if selected.contains(row) { selected.remove(row) } else { selected.insert(row) }
            anchor = row
        case .extend:
            guard let anchor, let range = range(from: anchor, to: row, in: order) else {
                selected = [row]
                anchor = row
                cursor = row
                return
            }
            selected = Set(range)
        }
        cursor = row
    }

    public mutating func selectAll(_ order: [RowID]) {
        selected = Set(order)
        anchor = order.first
        cursor = order.last
    }

    public mutating func set(_ rows: Set<RowID>, order: [RowID]) {
        selected = rows
        let ordered = order.filter(rows.contains)
        anchor = ordered.first
        cursor = ordered.last
    }

    public mutating func clear() {
        selected = []
        anchor = nil
        cursor = nil
    }

    /// Arrow-key navigation: moves the cursor by `delta` rows, extending the selection with ⇧.
    public mutating func move(by delta: Int, extend: Bool, order: [RowID]) {
        guard !order.isEmpty else { return }
        let currentIndex = cursor.flatMap { order.firstIndex(of: $0) }
        let target: Int = if let currentIndex {
            min(max(currentIndex + delta, 0), order.count - 1)
        } else {
            delta >= 0 ? 0 : order.count - 1
        }
        let row = order[target]
        if extend, let anchor, let range = range(from: anchor, to: row, in: order) {
            selected = Set(range)
        } else {
            selected = [row]
            anchor = row
        }
        cursor = row
    }

    /// Drops rows that no longer exist.
    public mutating func prune(keeping order: [RowID]) {
        let existing = Set(order)
        selected.formIntersection(existing)
        if let anchor, !existing.contains(anchor) { self.anchor = nil }
        if let cursor, !existing.contains(cursor) { self.cursor = selected.isEmpty ? nil : order.first(where: selected.contains) }
    }

    private func range(from start: RowID, to end: RowID, in order: [RowID]) -> ArraySlice<RowID>? {
        guard let first = order.firstIndex(of: start), let last = order.firstIndex(of: end) else { return nil }
        return order[min(first, last) ... max(first, last)]
    }
}
