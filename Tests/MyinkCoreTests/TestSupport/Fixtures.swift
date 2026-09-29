import Foundation
@testable import MyinkCore

/// Small builders that keep tests readable.
enum Fixture {
    static func textItem(_ name: String) -> ShelfItem {
        ShelfItem(displayName: name, content: .snippet(Snippet(kind: .text, representations: [])))
    }

    static func ownedItem(_ name: String, directory: String) -> ShelfItem {
        ShelfItem(displayName: name, content: .ownedFile(OwnedFile(relativePath: "\(directory)/\(name)", origin: .copy)))
    }

    static func referenceItem(_ path: String) -> ShelfItem {
        ShelfItem(
            displayName: (path as NSString).lastPathComponent,
            content: .fileReference(FileReference(bookmark: Data(), lastKnownPath: path, isDirectory: false))
        )
    }

    static func entry(_ names: String..., locked: Bool = false) -> ShelfEntry {
        ShelfEntry(items: names.map(textItem), isLocked: locked)
    }

    static func names(_ state: ShelfState) -> [String] {
        state.entries.map { $0.items.map(\.displayName).joined(separator: "+") }
    }
}
