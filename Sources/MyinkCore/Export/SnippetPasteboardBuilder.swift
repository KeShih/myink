import AppKit

/// Rebuilds the pasteboard data of a snippet for dragging out, copying or Quick Look.
public enum SnippetPasteboardBuilder {
    /// The representations to offer, in order. Links always carry URL, title and plain text so
    /// Finder can make a `.webloc` and text fields receive the address.
    public static func representations(for snippet: Snippet, load: (Representation) -> Data?) -> [CapturedRepresentation] {
        var result: [CapturedRepresentation] = []
        var seen = Set<String>()
        func add(_ type: String, _ data: Data) {
            guard !seen.contains(type) else { return }
            seen.insert(type)
            result.append(CapturedRepresentation(type: type, data: data))
        }
        if snippet.kind == .link, let url = snippet.url {
            add(TypeCatalog.url, Data(url.utf8))
            if let title = snippet.title { add(TypeCatalog.urlName, Data(title.utf8)) }
        }
        for representation in snippet.representations {
            if let data = load(representation) { add(representation.type, data) }
        }
        if snippet.kind == .link, let url = snippet.url {
            add(TypeCatalog.plainText, Data(url.utf8))
        }
        return result
    }

    public static func pasteboardItem(for snippet: Snippet, load: (Representation) -> Data?) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        for representation in representations(for: snippet, load: load) {
            item.setData(representation.data, forType: NSPasteboard.PasteboardType(representation.type))
        }
        return item
    }

    /// A file extension and data that best preview the snippet (for Quick Look and "Save as file").
    public static func previewFile(for snippet: Snippet, load: (Representation) -> Data?) -> (ext: String, data: Data)? {
        if snippet.kind == .link, let url = snippet.url {
            let plist: [String: String] = ["URL": url]
            if let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) {
                return ("webloc", data)
            }
        }
        let preferences: [(String, String)] = [
            (TypeCatalog.rtfd, "rtfd-flat"), (TypeCatalog.rtf, "rtf"), (TypeCatalog.html, "html"), (TypeCatalog.plainText, "txt")
        ]
        for (type, ext) in preferences {
            if let representation = snippet.representations.first(where: { $0.type == type }), let data = load(representation) {
                if ext == "rtfd-flat" {
                    // Flat RTFD can't be previewed directly; convert to RTF with attachments dropped.
                    if let attributed = NSAttributedString(rtfd: data, documentAttributes: nil),
                       let rtf = attributed.rtf(from: NSRange(location: 0, length: attributed.length)) {
                        return ("rtf", rtf)
                    }
                    continue
                }
                return (ext, data)
            }
        }
        if let preview = snippet.previewText, !preview.isEmpty {
            return ("txt", Data(preview.utf8))
        }
        return nil
    }
}
