import AppKit
import MyinkCore

/// Writes snippets out as real files (in Caches) so Quick Look and "Open" can show them.
struct PreviewMaterializer {
    let store: ShelfStore

    private var directory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? URL(filePath: NSTemporaryDirectory())
        return caches.appending(path: "dev.keshi.myink/Previews", directoryHint: .isDirectory)
    }

    /// A file showing the item: the file itself for file items, a generated preview for snippets.
    func url(for item: ShelfItem) -> URL? {
        switch item.content {
        case .fileReference, .ownedFile:
            return store.currentFileURL(for: item)
        case let .snippet(snippet):
            guard let preview = SnippetPasteboardBuilder.previewFile(for: snippet, load: store.data(for:)) else { return nil }
            let base = FileNaming.sanitized(item.displayName, fallback: "Snippet")
            let folder = directory.appending(path: item.id.uuidString, directoryHint: .isDirectory)
            let url = folder.appending(path: "\(base).\(preview.ext)")
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                if !FileManager.default.fileExists(atPath: url.path) {
                    try preview.data.write(to: url, options: .atomic)
                }
                return url
            } catch {
                Log.shelf.error("couldn't write preview: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        case .placeholder:
            return nil
        }
    }

    /// Clears generated previews (at launch).
    func purge() {
        try? FileManager.default.removeItem(at: directory)
    }
}
