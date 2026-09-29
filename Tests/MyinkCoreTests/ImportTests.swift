import AppKit
@testable import MyinkCore
import Testing

extension Tag {
    /// Tests that talk to the pasteboard server (need a logged-in GUI session).
    @Tag static var pasteboard: Self
}

private func item(_ pairs: [(String, String)]) -> PasteboardSnapshot.Item {
    PasteboardSnapshot.Item(types: pairs.map(\.0), data: Dictionary(uniqueKeysWithValues: pairs.map { ($0.0, Data($0.1.utf8)) }))
}

private func item(types: [String], data: [String: Data]) -> PasteboardSnapshot.Item {
    PasteboardSnapshot.Item(types: types, data: data)
}

@Suite("ImportClassifier")
struct ImportClassifierTests {
    let pngBytes = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3])

    @Test("Safari link: URL + title")
    func safariLink() {
        let candidate = ImportClassifier.classify(item([
            (TypeCatalog.url, "https://www.apple.com/mac/"),
            (TypeCatalog.urlName, "Mac - Apple"),
            (TypeCatalog.plainText, "https://www.apple.com/mac/")
        ]))
        guard case let .link(url, title, representations) = candidate else {
            Issue.record("expected link, got \(candidate)")
            return
        }
        #expect(url == "https://www.apple.com/mac/")
        #expect(title == "Mac - Apple")
        #expect(representations.map(\.type) == [TypeCatalog.url, TypeCatalog.urlName, TypeCatalog.plainText])
    }

    @Test("Link titles fall back to WebURLsWithTitles, then to non-URL plain text")
    func linkTitleFallbacks() throws {
        let plist = try PropertyListSerialization.data(
            fromPropertyList: [["https://a.example"], ["Example A"]],
            format: .binary,
            options: 0
        )
        let withTitles = item(
            types: [TypeCatalog.url, TypeCatalog.webURLsWithTitles],
            data: [TypeCatalog.url: Data("https://a.example".utf8), TypeCatalog.webURLsWithTitles: plist]
        )
        #expect(ImportClassifier.classify(withTitles) == .link(
            url: "https://a.example",
            title: "Example A",
            representations: [CapturedRepresentation(type: TypeCatalog.url, data: Data("https://a.example".utf8))]
        ))

        let chrome = ImportClassifier.classify(item([
            (TypeCatalog.url, "https://b.example\0"),
            (TypeCatalog.plainText, "https://b.example")
        ]))
        guard case let .link(url, title, _) = chrome else {
            Issue.record("expected link")
            return
        }
        #expect(url == "https://b.example")
        #expect(title == nil)
    }

    @Test("Browser image without a promise becomes an image named after the URL")
    func browserImage() {
        let candidate = ImportClassifier.classify(item(
            types: [TypeCatalog.png, TypeCatalog.url, TypeCatalog.html],
            data: [
                TypeCatalog.png: pngBytes,
                TypeCatalog.url: Data("https://cdn.example/photos/cat%20face.png?x=1".utf8),
                TypeCatalog.html: Data("<img>".utf8)
            ]
        ))
        #expect(candidate == .image(
            data: pngBytes,
            type: TypeCatalog.png,
            suggestedName: "cat face.png",
            sourceURL: "https://cdn.example/photos/cat%20face.png?x=1"
        ))
    }

    @Test("Compressed image formats win over TIFF")
    func prefersCompressed() {
        let candidate = ImportClassifier.classify(item(
            types: [TypeCatalog.tiff, TypeCatalog.jpeg],
            data: [TypeCatalog.tiff: Data([1]), TypeCatalog.jpeg: Data([2])]
        ))
        #expect(candidate == .image(data: Data([2]), type: TypeCatalog.jpeg, suggestedName: nil, sourceURL: nil))
    }

    @Test("Rich text with an embedded image stays text")
    func richTextWithImage() {
        let rtf = Data(#"{\rtf1\ansi Hello {\b world}}"#.utf8)
        let candidate = ImportClassifier.classify(item(
            types: [TypeCatalog.rtfd, TypeCatalog.rtf, TypeCatalog.tiff, TypeCatalog.plainText],
            data: [TypeCatalog.rtf: rtf, TypeCatalog.tiff: Data([1]), TypeCatalog.plainText: Data("Hello world".utf8)]
        ))
        guard case let .text(representations, preview) = candidate else {
            Issue.record("expected text, got \(candidate)")
            return
        }
        #expect(preview == "Hello world")
        #expect(representations.map(\.type) == [TypeCatalog.rtf, TypeCatalog.tiff, TypeCatalog.plainText])
    }

    @Test("Text previews come from plain text, RTF or tag-stripped HTML")
    func textPreviews() {
        let rtfOnly = ImportClassifier.classify(item([(TypeCatalog.rtf, #"{\rtf1\ansi Styled {\i text}}"#)]))
        guard case let .text(_, rtfPreview) = rtfOnly else {
            Issue.record("expected text")
            return
        }
        #expect(rtfPreview == "Styled text")

        let htmlOnly = ImportClassifier.classify(item([(TypeCatalog.html, "<p>Hello&nbsp;<b>there</b></p><script>x()</script>")]))
        guard case let .text(_, htmlPreview) = htmlOnly else {
            Issue.record("expected text")
            return
        }
        #expect(htmlPreview == "Hello there")
    }

    @Test("PDF data, custom data, file URLs and empty items")
    func otherKinds() {
        #expect(ImportClassifier.classify(item(types: [TypeCatalog.pdf], data: [TypeCatalog.pdf: Data([9])])) == .pdf(
            data: Data([9]),
            suggestedName: nil
        ))

        let raw = ImportClassifier.classify(item([("com.example.clip", "payload")]))
        #expect(raw == .raw(
            representations: [CapturedRepresentation(type: "com.example.clip", data: Data("payload".utf8))],
            description: "com.example.clip"
        ))

        #expect(ImportClassifier
            .classify(item([(TypeCatalog.fileURL, "file:///Users/me/a%20b.txt")])) == .fileURL(URL(filePath: "/Users/me/a b.txt")))
        #expect(ImportClassifier
            .classify(item([(TypeCatalog.url, "file:///Users/me/a.txt")])) == .fileURL(URL(filePath: "/Users/me/a.txt")))
        #expect(ImportClassifier.classify(item([])) == .nothing)
    }

    @Test("Text display names use the first line")
    func displayNames() {
        #expect(ImportClassifier.displayName(forText: "\n  First line  \nsecond") == "First line")
        #expect(ImportClassifier.displayName(forText: "") == "Text")
        #expect(ImportClassifier.displayName(forText: String(repeating: "x", count: 100), limit: 10) == "xxxxxxxxx…")
    }
}

@Suite("ItemFactory")
struct ItemFactoryTests {
    @Test("References bookmark the file and remember folders")
    func references() throws {
        let temp = try TempDirectory()
        let factory = ItemFactory(files: OwnedFileStore(layout: StorageLayout(root: temp.url.appending(path: "store"))))
        let file = try temp.file("docs/readme.md")
        let folder = try temp.directory("docs")
        let fileItem = try factory.reference(to: file)
        #expect(fileItem.displayName == "readme.md")
        guard case let .fileReference(reference) = fileItem.content else {
            Issue.record("expected reference")
            return
        }
        #expect(!reference.isDirectory)
        #expect(reference.lastKnownPath == file.path)
        guard case let .fileReference(folderReference) = try factory.reference(to: folder).content else {
            Issue.record("expected reference")
            return
        }
        #expect(folderReference.isDirectory)
    }

    @Test("TIFF image data is stored as PNG with a timestamped name")
    func tiffBecomesPNG() async throws {
        let temp = try TempDirectory()
        let store = OwnedFileStore(layout: StorageLayout(root: temp.url))
        let factory = ItemFactory(files: store)
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 4, height: 4).fill()
        image.unlockFocus()
        let tiff = try #require(image.tiffRepresentation)

        let made = try await factory.make(.image(data: tiff, type: TypeCatalog.tiff, suggestedName: nil, sourceURL: nil))
        let item = try #require(made)
        #expect(item.displayName.hasPrefix("Image "))
        #expect(item.displayName.hasSuffix(".png"))
        #expect(item.typeIdentifier == "public.png")
        guard case let .ownedFile(file) = item.content else {
            Issue.record("expected owned file")
            return
        }
        #expect(file.origin == .generated)
        let bytes = try Data(contentsOf: store.url(for: file.relativePath))
        #expect(bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }

    @Test("Suggested names keep or gain the right extension")
    func imageNames() {
        let now = Date()
        #expect(ItemFactory.fileName(suggested: "cat.png", fallbackPrefix: "Image", extension: "png", now: now) == "cat.png")
        #expect(ItemFactory.fileName(suggested: "cat", fallbackPrefix: "Image", extension: "png", now: now) == "cat.png")
        #expect(ItemFactory.fileName(suggested: "photo.jpg", fallbackPrefix: "Image", extension: "jpeg", now: now) == "photo.jpg")
        #expect(ItemFactory.fileName(suggested: "  ", fallbackPrefix: "Document", extension: "pdf", now: now).hasPrefix("Document "))
    }

    @Test("Links and text become snippets whose data is stored")
    func snippets() async throws {
        let temp = try TempDirectory()
        let store = OwnedFileStore(layout: StorageLayout(root: temp.url))
        let factory = ItemFactory(files: store)
        let representations = [
            CapturedRepresentation(type: TypeCatalog.url, data: Data("https://example.com/page".utf8)),
            CapturedRepresentation(type: TypeCatalog.urlName, data: Data("Example Page".utf8))
        ]
        let madeLink = try await factory.make(.link(
            url: "https://example.com/page",
            title: "Example Page",
            representations: representations
        ))
        let link = try #require(madeLink)
        #expect(link.displayName == "Example Page")
        guard case let .snippet(snippet) = link.content else {
            Issue.record("expected snippet")
            return
        }
        #expect(snippet.kind == .link)
        #expect(snippet.url == "https://example.com/page")
        #expect(snippet.representations.count == 2)
        #expect(try Data(contentsOf: store.url(for: snippet.representations[1].relativePath)) == Data("Example Page".utf8))
        #expect(link.ownedDirectories.count == 1)

        let untitled = try await factory.make(.link(url: "https://www.example.org/x", title: nil, representations: []))
        #expect(untitled?.displayName == "www.example.org")

        let text = try await factory.make(.text(
            representations: [CapturedRepresentation(type: TypeCatalog.plainText, data: Data("Hello\nWorld".utf8))],
            preview: "Hello\nWorld"
        ))
        #expect(text?.displayName == "Hello")
        #expect(text?.typeIdentifier == TypeCatalog.plainText)
        #expect(try await factory.make(.nothing) == nil)
    }

    @Test("Copies land in Myink's storage")
    func copies() async throws {
        let temp = try TempDirectory()
        let store = OwnedFileStore(layout: StorageLayout(root: temp.url.appending(path: "store")))
        let source = try temp.file("Screenshot.png", contents: "png")
        let id = UUID()
        let item = try await ItemFactory(files: store).copy(source, origin: .copy, id: id)
        #expect(item.id == id)
        #expect(item.displayName == "Screenshot.png")
        guard case let .ownedFile(file) = item.content else {
            Issue.record("expected owned file")
            return
        }
        #expect(FileManager.default.fileExists(atPath: store.url(for: file.relativePath).path))
    }
}

@Suite("Pasteboard round trips", .tags(.pasteboard), .serialized)
struct PasteboardRoundTripTests {
    private func withPasteboard(_ body: (NSPasteboard) throws -> Void) rethrows {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("dev.keshi.myink.test.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        try body(pasteboard)
    }

    @Test("Snapshots keep modern types and skip legacy, dynamic and promise types")
    func capture() {
        withPasteboard { pasteboard in
            let item = NSPasteboardItem()
            item.setString("Hello", forType: .string)
            item.setData(Data(#"{\rtf1 Hello}"#.utf8), forType: .rtf)
            item.setString("dynamic", forType: NSPasteboard.PasteboardType("dyn.ah62d4rv4gu8yc6durvwwaznwmuuha2pxsvw0e55bsmwca7d3sbwu"))
            item.setString("custom", forType: NSPasteboard.PasteboardType("com.example.custom"))
            pasteboard.clearContents()
            pasteboard.writeObjects([item])

            let snapshot = PasteboardSnapshot.capture(pasteboard)
            #expect(snapshot.items.count == 1)
            let captured = Set(snapshot.items[0].capturedRepresentations.map(\.type))
            #expect(captured == [TypeCatalog.plainText, TypeCatalog.rtf, "com.example.custom"])
            #expect(snapshot.items[0].string(TypeCatalog.plainText) == "Hello")
        }
    }

    @Test("Snippets replay their representations; links also carry URL, title and text")
    func replay() throws {
        let stored = [
            Representation(type: TypeCatalog.html, relativePath: "d/rep-0.html", byteCount: 3)
        ]
        let data = ["d/rep-0.html": Data("<a>".utf8)]
        let link = Snippet(kind: .link, representations: stored, title: "Title", url: "https://example.com")
        let representations = SnippetPasteboardBuilder.representations(for: link) { data[$0.relativePath] }
        #expect(representations.map(\.type) == [TypeCatalog.url, TypeCatalog.urlName, TypeCatalog.html, TypeCatalog.plainText])

        try withPasteboard { pasteboard in
            pasteboard.clearContents()
            pasteboard.writeObjects([SnippetPasteboardBuilder.pasteboardItem(for: link) { data[$0.relativePath] }])
            let readItem = try #require(pasteboard.pasteboardItems?.first)
            #expect(readItem.string(forType: .URL) == "https://example.com")
            #expect(readItem.string(forType: .string) == "https://example.com")
            #expect(readItem.string(forType: .html) == "<a>")
        }
    }

    @Test("Preview files: links become .webloc, text prefers RTF")
    func previewFiles() throws {
        let link = Snippet(kind: .link, representations: [], url: "https://example.com")
        let linkPreview = try #require(SnippetPasteboardBuilder.previewFile(for: link) { _ in nil })
        #expect(linkPreview.ext == "webloc")
        let text = Snippet(kind: .text, representations: [
            Representation(type: TypeCatalog.plainText, relativePath: "t", byteCount: 1),
            Representation(type: TypeCatalog.rtf, relativePath: "r", byteCount: 1)
        ])
        let textPreview = try #require(SnippetPasteboardBuilder.previewFile(for: text) { Data($0.relativePath.utf8) })
        #expect(textPreview.ext == "rtf")
        let fallback = Snippet(kind: .raw, representations: [], previewText: "hi")
        #expect(SnippetPasteboardBuilder.previewFile(for: fallback) { _ in nil }?.ext == "txt")
    }
}

@Suite("Drag policies")
struct DragPolicyTests {
    @Test("External drops never answer .move", arguments: [
        NSDragOperation.every, [.copy, .move], [.move], [.move, .generic], [.link, .move], []
    ])
    func dropNeverMoves(mask: NSDragOperation) {
        let operation = DropPolicy.operation(sourceMask: mask, isInternal: false)
        #expect(!operation.contains(.move))
        #expect(operation.isEmpty || mask.contains(operation))
    }

    @Test("Drop answers follow copy → generic → link; internal drags move")
    func dropPreference() {
        #expect(DropPolicy.operation(sourceMask: .every, isInternal: false) == .copy)
        #expect(DropPolicy.operation(sourceMask: [.generic, .link], isInternal: false) == .generic)
        #expect(DropPolicy.operation(sourceMask: [.link], isInternal: false) == .link)
        #expect(DropPolicy.operation(sourceMask: [.move], isInternal: false) == [])
        #expect(DropPolicy.operation(sourceMask: [.move, .generic], isInternal: true) == .move)
    }

    @Test("Source masks: references follow Finder rules, everything else copies")
    func sourceMasks() {
        #expect(DragOutPolicy.sourceMask(for: [.reference], isLocal: false) == [.copy, .move, .generic])
        #expect(DragOutPolicy.sourceMask(for: [.owned], isLocal: false) == .copy)
        #expect(DragOutPolicy.sourceMask(for: [.reference, .snippet], isLocal: false) == .copy)
        #expect(DragOutPolicy.sourceMask(for: [.owned], isLocal: true) == [.move, .generic])
        #expect(!DragOutPolicy.sourceMask(for: [.reference], isLocal: false).contains(.link))
        #expect(!DragOutPolicy.sourceMask(for: [.reference], isLocal: false).contains(.delete))
    }

    @Test("Outcomes: .generic counts as a move")
    func outcomes() {
        #expect(DragOutPolicy.outcome(of: []) == .cancelled)
        #expect(DragOutPolicy.outcome(of: .copy) == .copied)
        #expect(DragOutPolicy.outcome(of: .move) == .moved)
        #expect(DragOutPolicy.outcome(of: .generic) == .moved)
        #expect(DragOutPolicy.outcome(of: .link) == .linked)
        #expect(DragOutPolicy.outcome(of: .delete) == .deleted)
    }

    @Test("Removal after drag-out respects locks, keep-after-drag-out and fn")
    func removal() {
        func remove(
            _ outcome: DragOutPolicy.Outcome = .moved,
            locked: Bool = false,
            keep: Bool = false,
            fn: Bool = false,
            onShelf: Bool = false
        ) -> Bool {
            DragOutPolicy.shouldRemove(outcome: outcome, isLocked: locked, keepAfterDragOut: keep, fnHeld: fn, droppedOnShelf: onShelf)
        }
        #expect(remove())
        #expect(remove(.copied))
        #expect(!remove(.cancelled))
        #expect(!remove(onShelf: true))
        #expect(!remove(locked: true))
        #expect(remove(locked: true, fn: true))
        #expect(!remove(fn: true))
        #expect(!remove(keep: true))
        #expect(remove(keep: true, fn: true))
        #expect(!remove(.cancelled, fn: true))
    }
}
