import AppKit
import MyinkCore
import QuickLookThumbnailing
import UniformTypeIdentifiers

/// Images for shelf cells: an immediate icon (Finder icon, or a drawn card for snippets), upgraded to a
/// Quick Look thumbnail generated in the background and cached by item, size and modification date.
final class ThumbnailProvider {
    private let cache = NSCache<NSString, NSImage>()
    private var pending: [String: [(NSImage) -> Void]] = [:]

    init() {
        cache.countLimit = 500
    }

    /// An image to show right away.
    func immediateImage(for item: ShelfItem, url: URL?, size: CGFloat) -> NSImage {
        switch item.content {
        case .fileReference, .ownedFile:
            if let url, FileManager.default.fileExists(atPath: url.path) {
                return NSWorkspace.shared.icon(forFile: url.path)
            }
            if let type = item.typeIdentifier.flatMap(UTType.init) {
                return NSWorkspace.shared.icon(for: type)
            }
            return NSWorkspace.shared.icon(for: .item)
        case let .snippet(snippet):
            return Self.card(for: snippet, title: item.displayName, size: size)
        case .placeholder:
            return Self.symbol("arrow.down.circle.dotted", size: size)
        }
    }

    /// Generates (or fetches) a Quick Look thumbnail for a file item; `completion` runs on the main actor.
    func thumbnail(for item: ShelfItem, url: URL?, size: CGFloat, scale: CGFloat, completion: @escaping (NSImage) -> Void) {
        guard let url, item.isFileBacked else { return }
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let key = "\(item.id.uuidString)-\(Int(size * scale))-\(Int(modified))"
        if let cached = cache.object(forKey: key as NSString) {
            completion(cached)
            return
        }
        if pending[key] != nil {
            pending[key]?.append(completion)
            return
        }
        pending[key] = [completion]
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: size, height: size), scale: scale, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { @Sendable [weak self] representation, _ in
            let cgImage = representation?.cgImage
            Task { @MainActor in
                self?.deliver(cgImage, key: key, pointSize: size)
            }
        }
    }

    private func deliver(_ cgImage: CGImage?, key: String, pointSize: CGFloat) {
        let callbacks = pending.removeValue(forKey: key) ?? []
        guard let cgImage else { return }
        let aspect = CGFloat(cgImage.width) / max(CGFloat(cgImage.height), 1)
        let size = aspect >= 1 ? NSSize(width: pointSize, height: pointSize / aspect) : NSSize(width: pointSize * aspect, height: pointSize)
        let image = NSImage(cgImage: cgImage, size: size)
        cache.setObject(image, forKey: key as NSString)
        for callback in callbacks {
            callback(image)
        }
    }

    // MARK: Drawn images

    static func symbol(_ name: String, size: CGFloat, color: NSColor = .secondaryLabelColor) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: size * 0.55, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) ?? NSImage()
    }

    /// A small "paper" card: text snippets show their first lines, links a globe and the host.
    static func card(for snippet: Snippet, title: String, size: CGFloat) -> NSImage {
        let cardSize = NSSize(width: size * 0.82, height: size)
        return NSImage(size: cardSize, flipped: true) { rect in
            let card = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: size * 0.08, yRadius: size * 0.08)
            NSColor.textBackgroundColor.setFill()
            card.fill()
            NSColor.separatorColor.setStroke()
            card.lineWidth = 1
            card.stroke()
            let inset = rect.insetBy(dx: size * 0.09, dy: size * 0.09)
            switch snippet.kind {
            case .link:
                let glyph = symbol("link", size: size * 0.9, color: .controlAccentColor)
                let glyphSize = glyph.size
                glyph.draw(in: NSRect(x: rect.midX - glyphSize.width / 2, y: inset.minY + size * 0.08, width: glyphSize.width, height: glyphSize.height))
                let host = snippet.url.flatMap { URL(string: $0)?.host() } ?? title
                draw(host, in: NSRect(x: inset.minX, y: rect.midY + size * 0.08, width: inset.width, height: inset.maxY - rect.midY), size: size * 0.1, color: .secondaryLabelColor)
            case .text:
                draw(snippet.previewText ?? title, in: inset, size: size * 0.085, color: .labelColor)
            case .raw:
                let glyph = symbol("doc.on.clipboard", size: size, color: .secondaryLabelColor)
                let glyphSize = glyph.size
                glyph.draw(in: NSRect(x: rect.midX - glyphSize.width / 2, y: rect.midY - glyphSize.height / 2, width: glyphSize.width, height: glyphSize.height))
            }
            return true
        }
    }

    private static func draw(_ text: String, in rect: NSRect, size: CGFloat, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: max(size, 5)),
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
        (String(text.prefix(400)) as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attributes)
    }
}

extension ShelfItem {
    /// Items whose content is a file on disk (referenced or owned).
    var isFileBacked: Bool {
        switch content {
        case .fileReference, .ownedFile: true
        case .snippet, .placeholder: false
        }
    }

    var isSnippet: Bool {
        if case .snippet = content { return true }
        return false
    }
}
