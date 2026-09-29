import Foundation

/// One tile on the shelf. An entry with more than one item is a *stack*.
public struct ShelfEntry: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public var items: [ShelfItem]
    /// Locked entries stay on the shelf after being dragged out.
    public var isLocked: Bool
    public var addedAt: Date

    public init(id: UUID = UUID(), items: [ShelfItem], isLocked: Bool = false, addedAt: Date = Date()) {
        self.id = id
        self.items = items
        self.isLocked = isLocked
        self.addedAt = addedAt
    }

    public var isStack: Bool {
        items.count > 1
    }
}

/// A single thing held by Myink: a reference to a file elsewhere, a file Myink owns, or a snippet of
/// pasteboard data (text, link, …).
public struct ShelfItem: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public var displayName: String
    /// Uniform Type Identifier of the content, when known (e.g. `public.png`, `public.folder`).
    public var typeIdentifier: String?
    public var content: ItemContent
    public var addedAt: Date
    /// Where the content came from (e.g. the web page URL of a dragged image), informational only.
    public var sourceURL: String?

    public init(
        id: UUID = UUID(),
        displayName: String,
        typeIdentifier: String? = nil,
        content: ItemContent,
        addedAt: Date = Date(),
        sourceURL: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.typeIdentifier = typeIdentifier
        self.content = content
        self.addedAt = addedAt
        self.sourceURL = sourceURL
    }

    public var isPlaceholder: Bool {
        if case .placeholder = content { return true }
        return false
    }

    /// Relative paths under the Items directory that this item's data lives in.
    public var ownedRelativePaths: [String] {
        switch content {
        case let .ownedFile(file): [file.relativePath]
        case let .snippet(snippet): snippet.representations.map(\.relativePath)
        case .fileReference, .placeholder: []
        }
    }

    /// The top-level directories under Items/ that hold this item's data.
    public var ownedDirectories: Set<String> {
        Set(ownedRelativePaths.compactMap { $0.split(separator: "/").first.map(String.init) })
    }
}

public enum ItemContent: Codable, Sendable, Hashable {
    /// A file or folder somewhere on disk, tracked through a bookmark so it survives moves and renames.
    case fileReference(FileReference)
    /// A file stored in Myink's own Items directory (received promise, copied temp file, image data…).
    case ownedFile(OwnedFile)
    /// Pasteboard representations replayed verbatim when dragged out (text, links, clippings).
    case snippet(Snippet)
    /// An import still in progress. Never persisted.
    case placeholder(Placeholder)
}

public struct FileReference: Codable, Sendable, Hashable {
    public var bookmark: Data
    public var lastKnownPath: String
    public var isDirectory: Bool

    public init(bookmark: Data, lastKnownPath: String, isDirectory: Bool) {
        self.bookmark = bookmark
        self.lastKnownPath = lastKnownPath
        self.isDirectory = isDirectory
    }
}

public struct OwnedFile: Codable, Sendable, Hashable {
    public enum Origin: String, Codable, Sendable {
        /// Received from a file promise (Photos, Mail, browser images…).
        case promise
        /// Copied from a temporary or app-private location.
        case copy
        /// Copied from a removable or network volume.
        case volumeCopy
        /// Written by Myink from pasteboard data (image or PDF data).
        case generated
    }

    /// Path relative to the Items directory, e.g. `"3F2A…/Photo.jpg"`.
    public var relativePath: String
    public var origin: Origin

    public init(relativePath: String, origin: Origin) {
        self.relativePath = relativePath
        self.origin = origin
    }
}

public struct Snippet: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable {
        case link, text, raw
    }

    public var kind: Kind
    public var representations: [Representation]
    public var title: String?
    public var previewText: String?
    /// For links: the URL string.
    public var url: String?

    public init(kind: Kind, representations: [Representation], title: String? = nil, previewText: String? = nil, url: String? = nil) {
        self.kind = kind
        self.representations = representations
        self.title = title
        self.previewText = previewText
        self.url = url
    }
}

/// One stored pasteboard representation of a snippet.
public struct Representation: Codable, Sendable, Hashable {
    /// Pasteboard type identifier, e.g. `public.utf8-plain-text`.
    public var type: String
    /// Path of the data file relative to the Items directory.
    public var relativePath: String
    public var byteCount: Int

    public init(type: String, relativePath: String, byteCount: Int) {
        self.type = type
        self.relativePath = relativePath
        self.byteCount = byteCount
    }
}

public struct Placeholder: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable {
        case copying, receiving, writing
    }

    public var kind: Kind

    public init(kind: Kind) {
        self.kind = kind
    }
}

/// Whether a referenced file can currently be reached. Computed at runtime, never persisted.
public enum Availability: String, Codable, Sendable, Hashable {
    case available
    /// The file no longer exists (deleted, or moved somewhere the bookmark can't follow).
    case missing
    /// The file sits in a Trash folder.
    case inTrash
    /// The volume holding the file isn't mounted.
    case offline
}
