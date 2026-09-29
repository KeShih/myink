import Foundation
@testable import MyinkCore
import Testing

@Suite("ShelfState")
struct ShelfStateTests {
    private func state(_ entries: ShelfEntry...) -> ShelfState {
        ShelfState(entries: entries)
    }

    @Test("Insert puts new entries at the top by default and clamps indices")
    func insert() {
        var shelf = state(Fixture.entry("a"), Fixture.entry("b"))
        shelf.insert([Fixture.entry("new")])
        #expect(Fixture.names(shelf) == ["new", "a", "b"])
        shelf.insert([Fixture.entry("end")], at: 99)
        #expect(Fixture.names(shelf) == ["new", "a", "b", "end"])
        shelf.insert([Fixture.entry("x"), Fixture.entry("y")], at: 1)
        #expect(Fixture.names(shelf) == ["new", "x", "y", "a", "b", "end"])
        #expect(shelf.itemCount == 6)
    }

    @Test("Removed entries form one batch and are restored in their original places")
    func removeAndRestore() {
        let a = Fixture.entry("a"), b = Fixture.entry("b"), c = Fixture.entry("c"), d = Fixture.entry("d")
        var shelf = state(a, b, c, d)
        let removed = shelf.remove(ItemSelection(entryIDs: [b.id, d.id]))
        #expect(Fixture.names(shelf) == ["a", "c"])
        #expect(removed.map(\.originalIndex) == [1, 3])
        #expect(Set(removed.map(\.batchID)).count == 1)
        #expect(shelf.recentlyRemoved.count == 2)

        let restored = shelf.restoreLatestBatch()
        #expect(restored == [b.id, d.id])
        #expect(Fixture.names(shelf) == ["a", "b", "c", "d"])
        #expect(shelf.recentlyRemoved.isEmpty)
        #expect(shelf.restoreLatestBatch().isEmpty)
    }

    @Test("Repeated restores walk back through older batches")
    func restoreOlderBatches() {
        let a = Fixture.entry("a"), b = Fixture.entry("b")
        var shelf = state(a, b)
        shelf.remove(ItemSelection(entryIDs: [a.id]), now: Date(timeIntervalSince1970: 1))
        shelf.remove(ItemSelection(entryIDs: [b.id]), now: Date(timeIntervalSince1970: 2))
        #expect(shelf.entries.isEmpty)
        shelf.restoreLatestBatch()
        #expect(Fixture.names(shelf) == ["b"])
        shelf.restoreLatestBatch()
        #expect(Fixture.names(shelf) == ["a", "b"])
    }

    @Test("Taking single items out of a stack leaves the rest; the taken items restore as their own entry")
    func removeFromStack() throws {
        let stack = Fixture.entry("one", "two", "three", locked: true)
        var shelf = state(Fixture.entry("top"), stack)
        let two = stack.items[1].id
        let removed = shelf.remove(ItemSelection(itemIDs: [two]))
        #expect(Fixture.names(shelf) == ["top", "one+three"])
        #expect(shelf.entries[1].id == stack.id)
        let part = try #require(removed.first)
        #expect(part.entry.id != stack.id)
        #expect(part.entry.items.map(\.displayName) == ["two"])
        #expect(part.entry.isLocked)

        shelf.restoreLatestBatch()
        #expect(Fixture.names(shelf) == ["top", "two", "one+three"])
    }

    @Test("Removing every item of a stack removes the entry itself")
    func removeWholeStackByItems() {
        let stack = Fixture.entry("one", "two")
        var shelf = state(stack)
        let removed = shelf.remove(ItemSelection(itemIDs: Set(stack.items.map(\.id))))
        #expect(shelf.entries.isEmpty)
        #expect(removed.first?.entry.id == stack.id)
    }

    @Test("Clear keeps locked entries unless asked to include them")
    func clear() {
        var shelf = state(Fixture.entry("a"), Fixture.entry("locked", locked: true), Fixture.entry("c"))
        shelf.clear(includingLocked: false)
        #expect(Fixture.names(shelf) == ["locked"])
        shelf.clear(includingLocked: true)
        #expect(shelf.entries.isEmpty)
        #expect(shelf.recentlyRemoved.count == 3)
    }

    @Test("Pruning drops old and excess removals and reports directories nothing uses anymore")
    func prune() {
        let old = ShelfEntry(items: [Fixture.ownedItem("old.png", directory: "D-old")])
        let recent = ShelfEntry(items: [Fixture.ownedItem("new.png", directory: "D-new")])
        let live = ShelfEntry(items: [Fixture.ownedItem("live.png", directory: "D-live")])
        var shelf = state(live)
        shelf.recentlyRemoved = [
            RemovedEntry(entry: recent, removedAt: Date(timeIntervalSince1970: 1000), batchID: UUID(), originalIndex: 0),
            RemovedEntry(entry: old, removedAt: Date(timeIntervalSince1970: 0), batchID: UUID(), originalIndex: 0)
        ]
        #expect(shelf.referencedOwnedDirectories() == ["D-old", "D-new", "D-live"])

        let byAge = shelf.pruneRecentlyRemoved(now: Date(timeIntervalSince1970: 1000), maxCount: 50, maxAge: 500)
        #expect(byAge == ["D-old"])
        #expect(shelf.recentlyRemoved.count == 1)

        let byCount = shelf.pruneRecentlyRemoved(now: Date(timeIntervalSince1970: 1000), maxCount: 0, maxAge: 500)
        #expect(byCount == ["D-new"])
        #expect(shelf.pruneRecentlyRemoved(now: Date(timeIntervalSince1970: 1000), maxCount: 0, maxAge: 500).isEmpty)
    }

    @Test("Discard forgets entries without recording them")
    func discard() {
        let owned = ShelfEntry(items: [Fixture.ownedItem("x.png", directory: "D1")])
        var shelf = state(owned, Fixture.entry("keep"))
        let orphaned = shelf.discard(ItemSelection(entryIDs: [owned.id]))
        #expect(orphaned == ["D1"])
        #expect(shelf.recentlyRemoved.isEmpty)
        #expect(Fixture.names(shelf) == ["keep"])
    }

    @Test("Placeholders are never persisted")
    func persistable() {
        let placeholder = ShelfItem(displayName: "Receiving…", content: .placeholder(Placeholder(kind: .receiving)))
        let mixed = ShelfEntry(items: [Fixture.textItem("ready"), placeholder])
        let pending = ShelfEntry(items: [placeholder])
        let shelf = state(mixed, pending)
        #expect(Fixture.names(shelf.persistable) == ["ready"])
    }

    @Test("Moving entries keeps their order and lands at the drop position")
    func move() {
        let a = Fixture.entry("a"), b = Fixture.entry("b"), c = Fixture.entry("c"), d = Fixture.entry("d")
        var shelf = state(a, b, c, d)
        shelf.move([d.id], to: 0)
        #expect(Fixture.names(shelf) == ["d", "a", "b", "c"])
        shelf.move([d.id, a.id], to: 4)
        #expect(Fixture.names(shelf) == ["b", "c", "d", "a"])
        shelf.move([b.id], to: 2)
        #expect(Fixture.names(shelf) == ["c", "b", "d", "a"])
        shelf.move([UUID()], to: 0)
        #expect(Fixture.names(shelf) == ["c", "b", "d", "a"])
    }

    @Test("Merge builds a stack at the first entry's position; split undoes it")
    func mergeAndSplit() throws {
        let a = Fixture.entry("a"), b = Fixture.entry("b"), c = Fixture.entry("c")
        var shelf = state(a, b, c)
        let mergedID = shelf.merge([c.id, a.id])
        let merged = try #require(mergedID)
        #expect(merged == a.id)
        #expect(Fixture.names(shelf) == ["a+c", "b"])

        let singles = shelf.split(merged)
        #expect(singles.count == 2)
        #expect(singles.first == a.id)
        #expect(Fixture.names(shelf) == ["a", "c", "b"])
        #expect(shelf.split(b.id).isEmpty)
    }

    @Test("Items can move from one stack into another entry")
    func moveItemsIntoEntry() {
        let stack = Fixture.entry("one", "two")
        let target = Fixture.entry("target")
        var shelf = state(stack, target)
        shelf.moveItems([stack.items[0].id], intoEntry: target.id)
        #expect(Fixture.names(shelf) == ["two", "target+one"])
        shelf.moveItems([stack.items[1].id], intoEntry: target.id)
        #expect(Fixture.names(shelf) == ["target+one+two"])
    }

    @Test("Toggle-all locks everything, then unlocks when everything is locked")
    func toggleAllLocks() {
        var shelf = state(Fixture.entry("a", locked: true), Fixture.entry("b"))
        shelf.toggleAllLocks()
        #expect(shelf.entries.allSatisfy { $0.isLocked })
        shelf.toggleAllLocks()
        #expect(shelf.entries.allSatisfy { !$0.isLocked })
        shelf.setLocked(true, entries: [shelf.entries[1].id])
        #expect(shelf.entries.map(\.isLocked) == [false, true])
    }

    @Test("Lookups find entries by referenced path and items by ID; updates apply in place")
    func lookups() throws {
        let reference = ShelfEntry(items: [Fixture.referenceItem("/Users/me/file.txt")])
        var shelf = state(Fixture.entry("a"), reference)
        #expect(shelf.entryReferencing(path: "/Users/me/file.txt")?.id == reference.id)
        #expect(shelf.entryReferencing(path: "/elsewhere") == nil)
        let itemID = reference.items[0].id
        shelf.updateItem(itemID) { $0.displayName = "renamed.txt" }
        let renamed = try #require(shelf.item(withID: itemID))
        #expect(renamed.displayName == "renamed.txt")
        shelf.replaceItem(itemID, with: Fixture.textItem("replaced"))
        #expect(Fixture.names(shelf) == ["a", "replaced"])
        shelf.append([Fixture.textItem("more")], toEntry: reference.id)
        #expect(Fixture.names(shelf) == ["a", "replaced+more"])
    }

    @Test("State round-trips through JSON")
    func codable() throws {
        var shelf = state(Fixture.entry("a", "b", locked: true), ShelfEntry(items: [Fixture.referenceItem("/tmp/x")]))
        shelf.remove(ItemSelection(entryIDs: [shelf.entries[1].id]))
        let data = try JSONEncoder().encode(shelf)
        #expect(try JSONDecoder().decode(ShelfState.self, from: data) == shelf)
    }
}

@Suite("ShelfState extraction")
struct ShelfStateExtractionTests {
    @Test("Items pulled out of a stack form a new entry at the drop position")
    func extract() throws {
        let stack = Fixture.entry("one", "two", "three")
        let other = Fixture.entry("other")
        var shelf = ShelfState(entries: [stack, other])
        let extracted = shelf.extractItems([stack.items[1].id], toNewEntryAt: 2)
        let newID = try #require(extracted)
        #expect(Fixture.names(shelf) == ["one+three", "other", "two"])
        #expect(shelf.entries[2].id == newID)

        let whole = Fixture.entry("x", "y")
        var second = ShelfState(entries: [whole, Fixture.entry("z")])
        second.extractItems(Set(whole.items.map(\.id)), toNewEntryAt: 2)
        #expect(Fixture.names(second) == ["z", "x+y"])
        let nothing = second.extractItems([UUID()], toNewEntryAt: 0)
        #expect(nothing == nil)
    }
}

@Suite("ShelfState placeholders in Recently Removed")
struct ShelfStatePlaceholderTests {
    @Test("A placeholder removed mid-import can still be completed, and is never persisted")
    func completeAfterRemoval() {
        let placeholder = ShelfItem(displayName: "…", content: .placeholder(Placeholder(kind: .receiving)))
        let entry = ShelfEntry(items: [placeholder])
        var shelf = ShelfState(entries: [entry])
        shelf.clear(includingLocked: true)
        #expect(shelf.persistable.recentlyRemoved.isEmpty)
        #expect(shelf.itemAnywhere(withID: placeholder.id)?.isPlaceholder == true)
        let finished = ShelfItem(
            id: placeholder.id,
            displayName: "photo.jpg",
            content: .ownedFile(OwnedFile(relativePath: "D/photo.jpg", origin: .promise))
        )
        let replaced = shelf.replaceItemAnywhere(placeholder.id, with: finished)
        #expect(replaced)
        let appended = shelf.appendAnywhere([Fixture.ownedItem("second.jpg", directory: "D")], besideItem: placeholder.id)
        #expect(appended)
        #expect(shelf.persistable.recentlyRemoved.first?.entry.items.count == 2)
        #expect(shelf.referencedOwnedDirectories() == ["D"])
        shelf.restoreLatestBatch()
        #expect(Fixture.names(shelf) == ["photo.jpg+second.jpg"])
        let missing = shelf.replaceItemAnywhere(UUID(), with: finished)
        #expect(!missing)
    }

    @Test("Discard also forgets failed placeholders that were moved to Recently Removed")
    func discardAnywhere() {
        let placeholder = ShelfItem(displayName: "…", content: .placeholder(Placeholder(kind: .copying)))
        var shelf = ShelfState(entries: [ShelfEntry(items: [placeholder])])
        shelf.clear(includingLocked: true)
        _ = shelf.discard(ItemSelection(itemIDs: [placeholder.id]))
        #expect(shelf.recentlyRemoved.isEmpty)
    }
}
