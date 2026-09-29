import Foundation

/// An entry that was removed from the shelf and can be restored.
public struct RemovedEntry: Codable, Sendable, Hashable, Identifiable {
    public var entry: ShelfEntry
    public var removedAt: Date
    /// Entries removed by the same action share a batch and are restored together.
    public var batchID: UUID
    /// Index the entry had on the shelf, used to put it back in place.
    public var originalIndex: Int

    public var id: UUID {
        entry.id
    }

    public init(entry: ShelfEntry, removedAt: Date, batchID: UUID, originalIndex: Int) {
        self.entry = entry
        self.removedAt = removedAt
        self.batchID = batchID
        self.originalIndex = originalIndex
    }
}

/// Identifies what to remove: whole entries and/or individual items (e.g. single files of a stack).
public struct ItemSelection: Hashable, Sendable {
    public var entryIDs: Set<UUID>
    public var itemIDs: Set<UUID>

    public init(entryIDs: Set<UUID> = [], itemIDs: Set<UUID> = []) {
        self.entryIDs = entryIDs
        self.itemIDs = itemIDs
    }

    public var isEmpty: Bool {
        entryIDs.isEmpty && itemIDs.isEmpty
    }
}

/// Everything Myink persists: the shelf's entries (top to bottom) and the Recently Removed list
/// (newest first). All mutations are pure and unit-tested.
public struct ShelfState: Codable, Sendable, Hashable {
    public var entries: [ShelfEntry]
    public var recentlyRemoved: [RemovedEntry]

    public init(entries: [ShelfEntry] = [], recentlyRemoved: [RemovedEntry] = []) {
        self.entries = entries
        self.recentlyRemoved = recentlyRemoved
    }

    // MARK: Queries

    /// Number of items on the shelf; a stack counts each of its items.
    public var itemCount: Int {
        entries.reduce(0) { $0 + $1.items.count }
    }

    public func entryIndex(withID id: UUID) -> Int? {
        entries.firstIndex { $0.id == id }
    }

    public func entryIndex(containingItem itemID: UUID) -> Int? {
        entries.firstIndex { $0.items.contains { $0.id == itemID } }
    }

    public func item(withID id: UUID) -> ShelfItem? {
        for entry in entries {
            if let item = entry.items.first(where: { $0.id == id }) { return item }
        }
        return nil
    }

    /// The entry holding a reference to `path`, if any (used to avoid duplicates).
    public func entryReferencing(path: String) -> ShelfEntry? {
        entries.first { entry in
            entry.items.contains { item in
                if case let .fileReference(reference) = item.content { return reference.lastKnownPath == path }
                return false
            }
        }
    }

    /// The state as it should be written to disk: placeholders (imports in flight) are dropped.
    public var persistable: ShelfState {
        var copy = self
        copy.entries = entries.compactMap { entry in
            var entry = entry
            entry.items.removeAll(where: \.isPlaceholder)
            return entry.items.isEmpty ? nil : entry
        }
        return copy
    }

    /// Top-level directories under Items/ that live or recently removed entries still use.
    public func referencedOwnedDirectories() -> Set<String> {
        var directories = Set<String>()
        for entry in entries + recentlyRemoved.map(\.entry) {
            for item in entry.items {
                directories.formUnion(item.ownedDirectories)
            }
        }
        return directories
    }

    // MARK: Adding

    /// Inserts entries at `index` (clamped); `nil` puts them at the top.
    public mutating func insert(_ newEntries: [ShelfEntry], at index: Int? = nil) {
        let position = min(max(index ?? 0, 0), entries.count)
        entries.insert(contentsOf: newEntries, at: position)
    }

    /// Adds items to an existing entry (e.g. more files arriving from one file promise).
    public mutating func append(_ items: [ShelfItem], toEntry entryID: UUID) {
        guard let index = entryIndex(withID: entryID) else { return }
        entries[index].items.append(contentsOf: items)
    }

    /// Replaces an item in place (e.g. a placeholder once its import finished).
    public mutating func replaceItem(_ itemID: UUID, with newItem: ShelfItem) {
        guard let entryIndex = entryIndex(containingItem: itemID),
              let itemIndex = entries[entryIndex].items.firstIndex(where: { $0.id == itemID }) else { return }
        entries[entryIndex].items[itemIndex] = newItem
    }

    public mutating func updateItem(_ itemID: UUID, _ transform: (inout ShelfItem) -> Void) {
        guard let entryIndex = entryIndex(containingItem: itemID),
              let itemIndex = entries[entryIndex].items.firstIndex(where: { $0.id == itemID }) else { return }
        transform(&entries[entryIndex].items[itemIndex])
    }

    // MARK: Removing & restoring

    /// Removes the selection. Whole entries keep their identity; items taken out of a stack form a
    /// new entry in Recently Removed. When `record` is true the removal is restorable as one batch.
    @discardableResult
    public mutating func remove(
        _ selection: ItemSelection,
        batchID: UUID = UUID(),
        now: Date = Date(),
        record: Bool = true
    ) -> [RemovedEntry] {
        guard !selection.isEmpty else { return [] }
        var removed: [RemovedEntry] = []
        var kept: [ShelfEntry] = []
        for (index, entry) in entries.enumerated() {
            if selection.entryIDs.contains(entry.id) {
                removed.append(RemovedEntry(entry: entry, removedAt: now, batchID: batchID, originalIndex: index))
                continue
            }
            let taken = entry.items.filter { selection.itemIDs.contains($0.id) }
            guard !taken.isEmpty else {
                kept.append(entry)
                continue
            }
            let remaining = entry.items.filter { !selection.itemIDs.contains($0.id) }
            if remaining.isEmpty {
                removed.append(RemovedEntry(entry: entry, removedAt: now, batchID: batchID, originalIndex: index))
            } else {
                let part = ShelfEntry(items: taken, isLocked: entry.isLocked, addedAt: entry.addedAt)
                removed.append(RemovedEntry(entry: part, removedAt: now, batchID: batchID, originalIndex: index))
                var rest = entry
                rest.items = remaining
                kept.append(rest)
            }
        }
        entries = kept
        if record {
            recentlyRemoved.insert(contentsOf: removed, at: 0)
        }
        return removed
    }

    /// Removes every entry, or only unlocked ones.
    @discardableResult
    public mutating func clear(includingLocked: Bool, batchID: UUID = UUID(), now: Date = Date()) -> [RemovedEntry] {
        let ids = Set(entries.filter { includingLocked || !$0.isLocked }.map(\.id))
        return remove(ItemSelection(entryIDs: ids), batchID: batchID, now: now)
    }

    /// Puts back every entry of the most recent removal batch. Returns the restored entry IDs.
    @discardableResult
    public mutating func restoreLatestBatch() -> [UUID] {
        guard let batch = recentlyRemoved.first?.batchID else { return [] }
        return restore { $0.batchID == batch }
    }

    /// Puts back specific removed entries. Returns the restored entry IDs.
    @discardableResult
    public mutating func restore(_ ids: Set<UUID>) -> [UUID] {
        restore { ids.contains($0.id) }
    }

    private mutating func restore(where shouldRestore: (RemovedEntry) -> Bool) -> [UUID] {
        let toRestore = recentlyRemoved.filter(shouldRestore).sorted { $0.originalIndex < $1.originalIndex }
        guard !toRestore.isEmpty else { return [] }
        recentlyRemoved.removeAll(where: shouldRestore)
        for removed in toRestore {
            var entry = removed.entry
            if entryIndex(withID: entry.id) != nil {
                entry = ShelfEntry(items: entry.items, isLocked: entry.isLocked, addedAt: entry.addedAt)
            }
            insert([entry], at: removed.originalIndex)
        }
        return toRestore.map(\.entry.id)
    }

    /// Drops Recently Removed entries beyond `maxCount` or older than `maxAge`. Returns the owned
    /// directories that nothing references anymore and can be deleted from disk.
    public mutating func pruneRecentlyRemoved(now: Date, maxCount: Int, maxAge: TimeInterval) -> Set<String> {
        let before = referencedOwnedDirectories()
        var kept: [RemovedEntry] = []
        for removed in recentlyRemoved where kept.count < maxCount && now.timeIntervalSince(removed.removedAt) <= maxAge {
            kept.append(removed)
        }
        guard kept.count != recentlyRemoved.count else { return [] }
        recentlyRemoved = kept
        return before.subtracting(referencedOwnedDirectories())
    }

    /// Forgets entries without recording them (e.g. failed imports). Returns orphaned directories.
    public mutating func discard(_ selection: ItemSelection) -> Set<String> {
        let before = referencedOwnedDirectories()
        remove(selection, record: false)
        return before.subtracting(referencedOwnedDirectories())
    }

    // MARK: Organizing

    /// Moves entries (keeping their relative order) so they start at `index`, expressed in the
    /// current indexing (as a drop indicator between rows would report it).
    public mutating func move(_ ids: [UUID], to index: Int) {
        let idSet = Set(ids)
        let moving = entries.filter { idSet.contains($0.id) }
        guard !moving.isEmpty else { return }
        let before = entries.prefix(min(max(index, 0), entries.count)).count(where: { idSet.contains($0.id) })
        entries.removeAll { idSet.contains($0.id) }
        let target = min(max(index - before, 0), entries.count)
        entries.insert(contentsOf: moving, at: target)
    }

    /// Combines entries into one stack at the position of the first (in shelf order).
    /// Returns the ID of the resulting entry.
    @discardableResult
    public mutating func merge(_ ids: Set<UUID>) -> UUID? {
        let merging = entries.filter { ids.contains($0.id) }
        guard let first = merging.first, merging.count > 1 else { return merging.first?.id }
        var combined = first
        combined.items = merging.flatMap(\.items)
        let position = entryIndex(withID: first.id) ?? 0
        entries.removeAll { ids.contains($0.id) }
        entries.insert(combined, at: min(position, entries.count))
        return combined.id
    }

    /// Moves items (e.g. dragged out of one stack) into another entry, making it a stack.
    public mutating func moveItems(_ itemIDs: Set<UUID>, intoEntry targetID: UUID) {
        guard entryIndex(withID: targetID) != nil else { return }
        var moving: [ShelfItem] = []
        for index in entries.indices where entries[index].id != targetID {
            moving += entries[index].items.filter { itemIDs.contains($0.id) }
            entries[index].items.removeAll { itemIDs.contains($0.id) }
        }
        entries.removeAll { $0.items.isEmpty }
        if let target = entryIndex(withID: targetID) {
            entries[target].items.append(contentsOf: moving)
        }
    }

    /// Splits a stack into single-item entries at its position. Returns the new entry IDs.
    @discardableResult
    public mutating func split(_ id: UUID) -> [UUID] {
        guard let index = entryIndex(withID: id), entries[index].isStack else { return [] }
        let stack = entries[index]
        let singles = stack.items.enumerated().map { offset, item in
            ShelfEntry(id: offset == 0 ? stack.id : UUID(), items: [item], isLocked: stack.isLocked, addedAt: stack.addedAt)
        }
        entries.replaceSubrange(index ... index, with: singles)
        return singles.map(\.id)
    }

    public mutating func setLocked(_ locked: Bool, entries ids: Set<UUID>) {
        for index in entries.indices where ids.contains(entries[index].id) {
            entries[index].isLocked = locked
        }
    }

    /// Locks everything, or unlocks everything if all entries are already locked.
    public mutating func toggleAllLocks() {
        let lockAll = !entries.allSatisfy(\.isLocked)
        for index in entries.indices {
            entries[index].isLocked = lockAll
        }
    }
}
