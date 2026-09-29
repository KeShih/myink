import AppKit
import UniformTypeIdentifiers

/// What a pasteboard item should become on the shelf.
public enum ImportCandidate: Sendable, Equatable {
    /// A file URL that arrived through a pasteboard that isn't a drag (Services, ⌘V).
    case fileURL(URL)
    /// Image data without a file behind it: stored as an image file.
    case image(data: Data, type: String, suggestedName: String?, sourceURL: String?)
    /// PDF data without a file behind it: stored as a .pdf file.
    case pdf(data: Data, suggestedName: String?)
    /// A web link, replayed as URL + title + text.
    case link(url: String, title: String?, representations: [CapturedRepresentation])
    /// Styled or plain text, replayed with every captured representation.
    case text(representations: [CapturedRepresentation], preview: String)
    /// Anything else Myink can store, replayed verbatim.
    case raw(representations: [CapturedRepresentation], description: String)
    case nothing
}

/// Decides what a snapshot item becomes. Rules, first match wins:
/// file URL → image data (unless it's rich text with an image inside) → PDF data → web URL →
/// text → other storable data.
public enum ImportClassifier {
    public static func classify(_ item: PasteboardSnapshot.Item) -> ImportCandidate {
        if let fileURL = fileURL(in: item) {
            return .fileURL(fileURL)
        }
        let hasRichText = TypeCatalog.richTextTypes.contains { item.data[$0] != nil }
        let webURL = webURL(in: item)

        if !hasRichText, let (type, data) = imageData(in: item) {
            return .image(data: data, type: type, suggestedName: suggestedImageName(item: item, webURL: webURL), sourceURL: webURL)
        }
        if !hasRichText, let data = item.data[TypeCatalog.pdf] {
            return .pdf(data: data, suggestedName: item.string(TypeCatalog.urlName))
        }
        if let webURL {
            return .link(url: webURL, title: title(in: item, url: webURL), representations: item.capturedRepresentations)
        }
        if TypeCatalog.textTypes.contains(where: { item.data[$0] != nil }) {
            return .text(representations: item.capturedRepresentations, preview: previewText(in: item))
        }
        let representations = item.capturedRepresentations
        if let first = representations.first {
            let description = UTType(first.type)?.localizedDescription ?? first.type
            return .raw(representations: representations, description: description)
        }
        return .nothing
    }

    // MARK: Helpers

    /// A file URL from `public.file-url`, or a `file:` URL offered as a plain `public.url`.
    static func fileURL(in item: PasteboardSnapshot.Item) -> URL? {
        for type in [TypeCatalog.fileURL, TypeCatalog.url] {
            guard let string = item.string(type)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let url = URL(string: string), url.isFileURL else { continue }
            return (url as NSURL).filePathURL ?? url
        }
        return nil
    }

    static func webURL(in item: PasteboardSnapshot.Item) -> String? {
        guard let string = item.string(TypeCatalog.url)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !string.isEmpty,
              let url = URL(string: string), let scheme = url.scheme?.lowercased(), scheme != "file"
        else { return nil }
        return string
    }

    static func imageData(in item: PasteboardSnapshot.Item) -> (String, Data)? {
        for type in TypeCatalog.compressedImageTypes {
            if let data = item.data[type] { return (type, data) }
        }
        if let data = item.data[TypeCatalog.tiff] { return (TypeCatalog.tiff, data) }
        return nil
    }

    static func suggestedImageName(item: PasteboardSnapshot.Item, webURL: String?) -> String? {
        if let name = item.string(TypeCatalog.urlName)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        guard let webURL, let last = URL(string: webURL)?.lastPathComponent, !last.isEmpty, last != "/",
              !(last as NSString).pathExtension.isEmpty else { return nil }
        return last.removingPercentEncoding ?? last
    }

    static func title(in item: PasteboardSnapshot.Item, url: String) -> String? {
        if let name = item.string(TypeCatalog.urlName)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        if let plist = item.data[TypeCatalog.webURLsWithTitles],
           let lists = try? PropertyListSerialization.propertyList(from: plist, format: nil) as? [[String]],
           lists.count > 1, let first = lists[1].first, !first.isEmpty {
            return first
        }
        if let text = item.string(TypeCatalog.plainText)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty, text != url, !text.contains("\n") {
            return text
        }
        return nil
    }

    /// Plain-text preview: plain text, else text extracted from RTF, else HTML without tags.
    static func previewText(in item: PasteboardSnapshot.Item) -> String {
        let raw: String = if let text = item.string(TypeCatalog.plainText) ?? item.string(TypeCatalog.utf16Text) {
            text
        } else if let rtf = item.data[TypeCatalog.rtf], let attributed = NSAttributedString(rtf: rtf, documentAttributes: nil) {
            attributed.string
        } else if let rtfd = item.data[TypeCatalog.rtfd], let attributed = NSAttributedString(rtfd: rtfd, documentAttributes: nil) {
            attributed.string
        } else if let html = item.string(TypeCatalog.html) {
            strippingTags(html)
        } else {
            ""
        }
        return String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2000))
    }

    static func strippingTags(_ html: String) -> String {
        var text = html.replacingOccurrences(
            of: "<(script|style)[^>]*>.*?</\\1>",
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(of: "<br\\s*/?>|</p>|</div>|</li>", with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'"]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        return text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
    }

    /// A short single-line name for a text snippet.
    public static func displayName(forText preview: String, limit: Int = 60) -> String {
        let firstLine = preview.split(whereSeparator: \.isNewline).first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        guard !firstLine.isEmpty else { return "Text" }
        return firstLine.count > limit ? String(firstLine.prefix(limit - 1)) + "…" : firstLine
    }
}
