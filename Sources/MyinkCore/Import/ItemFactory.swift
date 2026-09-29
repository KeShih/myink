import AppKit
import UniformTypeIdentifiers

/// Turns import candidates and files into shelf items, writing any data Myink owns into the
/// Items directory. File work runs off the main actor.
public struct ItemFactory: Sendable {
    public let files: OwnedFileStore

    public init(files: OwnedFileStore) {
        self.files = files
    }

    /// A reference to a file or folder that stays where it is.
    public func reference(to url: URL, id: UUID = UUID(), now: Date = Date()) throws -> ShelfItem {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentTypeKey])
        let bookmark = try Bookmarks.create(for: url)
        return ShelfItem(
            id: id,
            displayName: url.lastPathComponent,
            typeIdentifier: values?.contentType?.identifier,
            content: .fileReference(FileReference(bookmark: bookmark, lastKnownPath: url.path, isDirectory: values?.isDirectory ?? false)),
            addedAt: now
        )
    }

    /// Copies a file or folder into Myink's storage.
    @concurrent
    public func copy(_ url: URL, origin: OwnedFile.Origin, id: UUID = UUID(), now: Date = Date()) async throws -> ShelfItem {
        let relativePath = try await files.copyIn(url)
        return ownedItem(relativePath: relativePath, origin: origin, id: id, now: now)
    }

    /// Wraps a file that already sits in the Items directory (e.g. a received file promise).
    public func ownedItem(
        relativePath: String,
        origin: OwnedFile.Origin,
        id: UUID = UUID(),
        now: Date = Date(),
        sourceURL: String? = nil
    ) -> ShelfItem {
        let url = files.url(for: relativePath)
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType?.identifier
            ?? UTType(filenameExtension: url.pathExtension)?.identifier
        return ShelfItem(
            id: id,
            displayName: url.lastPathComponent,
            typeIdentifier: type,
            content: .ownedFile(OwnedFile(relativePath: relativePath, origin: origin)),
            addedAt: now,
            sourceURL: sourceURL
        )
    }

    /// Builds an item from pasteboard data off the main actor (for large payloads).
    @concurrent
    public func make(_ candidate: ImportCandidate, id: UUID = UUID(), now: Date = Date()) async throws -> ShelfItem? {
        try makeNow(candidate, id: id, now: now)
    }

    /// Builds an item from pasteboard data synchronously. Returns nil for `.nothing` and file URLs
    /// (which go through `reference(to:)`/`copy(_:)`).
    public func makeNow(_ candidate: ImportCandidate, id: UUID = UUID(), now: Date = Date()) throws -> ShelfItem? {
        switch candidate {
        case .nothing, .fileURL:
            return nil

        case let .image(data, type, suggestedName, sourceURL):
            var bytes = data
            var imageType = UTType(type) ?? .image
            if imageType == .tiff, let png = NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]) {
                bytes = png
                imageType = .png
            }
            let ext = imageType.preferredFilenameExtension ?? "png"
            let name = Self.fileName(suggested: suggestedName, fallbackPrefix: "Image", extension: ext, now: now)
            let relativePath = try files.write(bytes, fileName: name)
            return ownedItem(relativePath: relativePath, origin: .generated, id: id, now: now, sourceURL: sourceURL)

        case let .pdf(data, suggestedName):
            let name = Self.fileName(suggested: suggestedName, fallbackPrefix: "Document", extension: "pdf", now: now)
            let relativePath = try files.write(data, fileName: name)
            return ownedItem(relativePath: relativePath, origin: .generated, id: id, now: now)

        case let .link(url, title, representations):
            var snippet = try storeSnippet(kind: .link, representations: representations)
            snippet.title = title
            snippet.url = url
            snippet.previewText = url
            let name = title ?? URL(string: url)?.host() ?? url
            return ShelfItem(
                id: id,
                displayName: ImportClassifier.displayName(forText: name, limit: 80),
                typeIdentifier: UTType.url.identifier,
                content: .snippet(snippet),
                addedAt: now,
                sourceURL: url
            )

        case let .text(representations, preview):
            var snippet = try storeSnippet(kind: .text, representations: representations)
            snippet.previewText = preview
            let primary = representations.first { TypeCatalog.textTypes.contains($0.type) }?.type ?? TypeCatalog.plainText
            return ShelfItem(
                id: id,
                displayName: ImportClassifier.displayName(forText: preview),
                typeIdentifier: primary,
                content: .snippet(snippet),
                addedAt: now
            )

        case let .raw(representations, description):
            let snippet = try storeSnippet(kind: .raw, representations: representations)
            return ShelfItem(
                id: id,
                displayName: description,
                typeIdentifier: representations.first?.type,
                content: .snippet(snippet),
                addedAt: now
            )
        }
    }

    /// Writes each representation into one new directory.
    func storeSnippet(kind: Snippet.Kind, representations: [CapturedRepresentation]) throws -> Snippet {
        let directory = try files.makeDirectory()
        var stored: [Representation] = []
        for (index, representation) in representations.enumerated() {
            let ext = UTType(representation.type)?.preferredFilenameExtension ?? "bin"
            let path = try files.write(representation.data, fileName: "rep-\(index).\(ext)", directory: directory)
            stored.append(Representation(type: representation.type, relativePath: path, byteCount: representation.data.count))
        }
        return Snippet(kind: kind, representations: stored)
    }

    static func fileName(suggested: String?, fallbackPrefix: String, extension ext: String, now: Date) -> String {
        guard let suggested = suggested?.trimmingCharacters(in: .whitespacesAndNewlines), !suggested.isEmpty else {
            return FileNaming.timestamped(fallbackPrefix, date: now, extension: ext)
        }
        let currentExt = (suggested as NSString).pathExtension.lowercased()
        let matches = currentExt == ext.lowercased() || (ext == "jpeg" && currentExt == "jpg") || (ext == "jpg" && currentExt == "jpeg")
        return matches ? suggested : "\(suggested).\(ext)"
    }
}
