import AppKit

/// Which operation the shelf reports when something is dropped on it.
public enum DropPolicy {
    /// External drops answer `.copy` (else `.generic`, else `.link`) and never `.move`: a source
    /// that sees `.move` may delete what was dragged (TextEdit deletes dragged text, Mail can move
    /// messages). Drags from the shelf onto itself rearrange, so they answer `.move`.
    public static func operation(sourceMask: NSDragOperation, isInternal: Bool) -> NSDragOperation {
        if isInternal {
            if sourceMask.contains(.move) { return .move }
            return sourceMask.contains(.generic) ? .generic : []
        }
        if sourceMask.contains(.copy) { return .copy }
        if sourceMask.contains(.generic) { return .generic }
        if sourceMask.contains(.link) { return .link }
        return []
    }
}

/// Rules for dragging items off the shelf.
public enum DragOutPolicy {
    public enum Kind: Sendable, Hashable {
        /// A file that stays where it is: Finder may move or copy it.
        case reference
        /// A file inside Myink's storage: always copied out, so the shelf's copy survives.
        case owned
        /// Replayed pasteboard data.
        case snippet
    }

    public enum Outcome: Sendable, Equatable {
        case cancelled, copied, moved, linked, deleted
    }

    /// The operations Myink offers. AppKit narrows this with the modifier keys: ⌥ leaves `.copy`,
    /// ⌘ leaves `.generic` (Finder performs a move). `.link` and `.delete` are never offered —
    /// they would make Finder create aliases or trash the original.
    public static func sourceMask(for kinds: some Sequence<Kind>, isLocal: Bool) -> NSDragOperation {
        if isLocal { return [.move, .generic] }
        var mask: NSDragOperation = [.copy, .move, .generic]
        for kind in kinds {
            mask.formIntersection(kind == .reference ? [.copy, .move, .generic] : [.copy])
        }
        return mask
    }

    public static func outcome(of operation: NSDragOperation) -> Outcome {
        if operation.isEmpty { return .cancelled }
        if operation.contains(.delete) { return .deleted }
        if operation.contains(.move) || operation.contains(.generic) { return .moved }
        if operation.contains(.copy) { return .copied }
        if operation.contains(.link) { return .linked }
        return .copied
    }

    /// Whether a dragged-out entry leaves the shelf. Locked entries (or everything, with
    /// "keep after drag-out") stay; holding fn during the drag inverts that for this drag.
    public static func shouldRemove(outcome: Outcome, isLocked: Bool, keepAfterDragOut: Bool, fnHeld: Bool, droppedOnShelf: Bool) -> Bool {
        guard outcome != .cancelled, !droppedOnShelf else { return false }
        var keep = isLocked || keepAfterDragOut
        if fnHeld { keep.toggle() }
        return !keep
    }
}
