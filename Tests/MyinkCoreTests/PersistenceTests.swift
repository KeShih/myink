import Foundation
@testable import MyinkCore
import Testing

@Suite("ManifestStore")
struct ManifestStoreTests {
    @Test("Saved state loads back; placeholders are dropped")
    func roundTrip() throws {
        let temp = try TempDirectory()
        let store = ManifestStore(layout: StorageLayout(root: temp.url))
        var state = ShelfState(entries: [Fixture.entry("a", "b", locked: true), Fixture.entry("c")])
        state.remove(ItemSelection(entryIDs: [state.entries[1].id]))
        state.insert([ShelfEntry(items: [ShelfItem(displayName: "…", content: .placeholder(Placeholder(kind: .receiving)))])])
        try store.save(state)
        #expect(store.load() == .loaded(state.persistable))
    }

    @Test("A missing manifest starts fresh")
    func fresh() throws {
        let temp = try TempDirectory()
        #expect(ManifestStore(layout: StorageLayout(root: temp.url)).load() == .fresh(quarantined: nil))
    }

    @Test("A corrupt manifest is quarantined and the backup is used")
    func recoversFromBackup() throws {
        let temp = try TempDirectory()
        let layout = StorageLayout(root: temp.url)
        let store = ManifestStore(layout: layout)
        let state = ShelfState(entries: [Fixture.entry("saved")])
        try store.save(state)
        store.refreshBackup()
        try Data("{ not json".utf8).write(to: layout.manifestURL)

        let result = store.load()
        guard case let .recovered(recovered, quarantined) = result else {
            Issue.record("expected recovery, got \(result)")
            return
        }
        #expect(recovered == state)
        let quarantinedURL = try #require(quarantined)
        #expect(FileManager.default.fileExists(atPath: quarantinedURL.path))
        #expect(quarantinedURL.lastPathComponent.hasPrefix("shelf.corrupt-"))
        #expect(!FileManager.default.fileExists(atPath: layout.manifestURL.path))
    }

    @Test("A corrupt manifest without backup starts fresh but keeps the bad file")
    func corruptWithoutBackup() throws {
        let temp = try TempDirectory()
        let layout = StorageLayout(root: temp.url)
        try Data("garbage".utf8).write(to: layout.manifestURL)
        guard case let .fresh(quarantined) = ManifestStore(layout: layout).load() else {
            Issue.record("expected fresh start")
            return
        }
        #expect(quarantined != nil)
    }

    @Test("Manifests from a newer version are not read (or overwritten)")
    func futureVersion() throws {
        let temp = try TempDirectory()
        let layout = StorageLayout(root: temp.url)
        let json = #"{"version": 99, "state": {"entries": [], "recentlyRemoved": []}}"#
        try Data(json.utf8).write(to: layout.manifestURL)
        guard case let .fresh(quarantined) = ManifestStore(layout: layout).load() else {
            Issue.record("expected fresh start")
            return
        }
        #expect(quarantined != nil)
    }
}

@Suite("OwnedFileStore")
struct OwnedFileStoreTests {
    @Test("Writes get unique names within a directory")
    func write() throws {
        let temp = try TempDirectory()
        let store = OwnedFileStore(layout: StorageLayout(root: temp.url))
        let first = try store.write(Data("one".utf8), fileName: "note.txt")
        let directory = String(first.split(separator: "/")[0])
        let second = try store.write(Data("two".utf8), fileName: "note.txt", directory: directory)
        #expect(first.hasSuffix("/note.txt"))
        #expect(second == "\(directory)/note 2.txt")
        #expect(try String(contentsOf: store.url(for: second), encoding: .utf8) == "two")
        let unsafe = try store.write(Data(), fileName: "../../evil:name")
        #expect(unsafe.split(separator: "/").count == 2)
        let itemsRoot = temp.url.appending(path: "Items").path + "/"
        #expect(store.url(for: unsafe).standardizedFileURL.path.hasPrefix(itemsRoot))
    }

    @Test("Copying brings the file into its own directory")
    func copyIn() async throws {
        let temp = try TempDirectory()
        let source = try temp.file("outside/report.pdf", contents: "%PDF")
        let store = OwnedFileStore(layout: StorageLayout(root: temp.url.appending(path: "store")))
        let path = try await store.copyIn(source)
        #expect(path.hasSuffix("/report.pdf"))
        #expect(try String(contentsOf: store.url(for: path), encoding: .utf8) == "%PDF")
        #expect(FileManager.default.fileExists(atPath: source.path))
        let renamed = try await store.copyIn(source, fileName: "Renamed.pdf")
        #expect(renamed.hasSuffix("/Renamed.pdf"))
    }

    @Test("Garbage collection removes only old, unreferenced directories")
    func garbageCollection() throws {
        let temp = try TempDirectory()
        let store = OwnedFileStore(layout: StorageLayout(root: temp.url))
        let kept = try String(store.write(Data(), fileName: "a").split(separator: "/")[0])
        let orphan = try String(store.write(Data(), fileName: "b").split(separator: "/")[0])

        #expect(store.collectGarbage(referenced: [kept], minimumAge: 3600).isEmpty)
        #expect(store.collectGarbage(referenced: [kept], minimumAge: 0) == [orphan])
        #expect(FileManager.default.fileExists(atPath: temp.url.appending(path: "Items/\(kept)").path))
        #expect(!FileManager.default.fileExists(atPath: temp.url.appending(path: "Items/\(orphan)").path))
    }

    @Test("Directory removal ignores path tricks")
    func removeDirectories() throws {
        let temp = try TempDirectory()
        let store = OwnedFileStore(layout: StorageLayout(root: temp.url.appending(path: "store")))
        let victim = try temp.file("victim.txt")
        store.removeDirectories(["..", "../victim.txt", ""])
        #expect(FileManager.default.fileExists(atPath: victim.path))
        let path = try store.write(Data("x".utf8), fileName: "x")
        #expect(store.totalSize() > 0)
        store.removeDirectories([String(path.split(separator: "/")[0])])
        #expect(!FileManager.default.fileExists(atPath: store.url(for: path).path))
    }
}

@Suite("Bookmarks")
struct BookmarksTests {
    @Test("A bookmark follows a renamed and moved file")
    func followsMoves() throws {
        let temp = try TempDirectory()
        let original = try temp.file("docs/draft.txt")
        let bookmark = try Bookmarks.create(for: original)
        let renamed = try temp.directory("elsewhere").appending(path: "final.txt")
        try FileManager.default.moveItem(at: original, to: renamed)

        let resolution = Bookmarks.resolve(bookmark, lastKnownPath: original.path, homeDirectory: temp.url.path)
        #expect(resolution.availability == .available)
        #expect(resolution.url?.resolvingSymlinksInPath().path == renamed.resolvingSymlinksInPath().path)
        #expect(resolution.isStale)
    }

    @Test("Deleted files are missing; files in a Trash are reported as trashed")
    func missingAndTrashed() throws {
        let temp = try TempDirectory()
        let doomed = try temp.file("doomed.txt")
        let doomedBookmark = try Bookmarks.create(for: doomed)
        try FileManager.default.removeItem(at: doomed)
        #expect(Bookmarks.resolve(doomedBookmark, lastKnownPath: doomed.path, homeDirectory: temp.url.path).availability == .missing)

        let trashed = try temp.file("trashed.txt")
        let trashedBookmark = try Bookmarks.create(for: trashed)
        let trash = try temp.directory(".Trash")
        try FileManager.default.moveItem(at: trashed, to: trash.appending(path: "trashed.txt"))
        let resolution = Bookmarks.resolve(trashedBookmark, lastKnownPath: trashed.path, homeDirectory: temp.url.path)
        #expect(resolution.availability == .inTrash)
    }

    @Test("Trash and volume paths are recognised")
    func paths() {
        #expect(Bookmarks.isInTrash(path: "/Users/me/.Trash/file", homeDirectory: "/Users/me"))
        #expect(Bookmarks.isInTrash(path: "/Volumes/USB/.Trashes/501/file", homeDirectory: "/Users/me"))
        #expect(!Bookmarks.isInTrash(path: "/Users/me/Documents/.Trash-notes", homeDirectory: "/Users/me"))
        #expect(Bookmarks.volumeRoot(of: "/Volumes/USB/Photos/a.jpg") == "/Volumes/USB")
        #expect(Bookmarks.volumeRoot(of: "/Users/me/a.jpg") == nil)
        #expect(Bookmarks.volumeIsOffline(bookmark: Data(), lastKnownPath: "/Volumes/Definitely-Not-Mounted-\(UUID())/a"))
    }
}

@Suite("FileLocationPolicy")
struct FileLocationPolicyTests {
    let policy = FileLocationPolicy(
        homeDirectory: "/Users/me",
        temporaryDirectory: "/var/folders/ab/xyz/T/",
        itemsRoot: "/Users/me/Library/Application Support/Myink/Items"
    )

    @Test("Ordinary files are referenced", arguments: [
        "/Users/me/Desktop/report.pdf",
        "/Users/me/Downloads/archive.zip",
        "/Users/me/Library/Mobile Documents/com~apple~CloudDocs/notes.txt",
        "/Users/me/Library/CloudStorage/Dropbox/a.txt",
        "/Applications/Safari.app"
    ])
    func references(path: String) {
        #expect(policy.decide(path: path, volume: VolumeTraits(), fileSize: 10) == .reference)
    }

    @Test("Transient and app-private files are copied", arguments: [
        "/private/var/folders/ab/xyz/T/TemporaryItems/NSIRD_screencaptureui_1/Screenshot.png",
        "/var/folders/ab/xyz/T/print.pdf",
        "/tmp/export.csv",
        "/private/tmp/export.csv",
        "/Users/me/Library/Containers/com.apple.mail/Data/Library/Mail Downloads/X/invoice.pdf",
        "/Users/me/Pictures/Photos Library.photoslibrary/originals/A/IMG.heic",
        "/Users/me/Library/Application Support/Myink/Items/ABC/file.png",
        "/Volumes/Data/.TemporaryItems/folders.501/TemporaryItems/x.png",
    ])
    func copies(path: String) {
        #expect(policy.decide(path: path, volume: VolumeTraits(), fileSize: 10) == .copy(.copy))
    }

    @Test("External volumes are copied only when enabled and within the size limit")
    func externalVolumes() {
        let usb = VolumeTraits(isRemovable: true, isEjectable: true, isLocal: true)
        let network = VolumeTraits(isLocal: false)
        #expect(policy.decide(path: "/Volumes/USB/a.mov", volume: usb, fileSize: 10) == .reference)
        var copying = policy
        copying.copyFromExternalVolumes = true
        #expect(copying.decide(path: "/Volumes/USB/a.mov", volume: usb, fileSize: 10) == .copy(.volumeCopy))
        #expect(copying.decide(path: "/Volumes/Share/a.mov", volume: network, fileSize: 10) == .copy(.volumeCopy))
        #expect(copying.decide(path: "/Volumes/USB/huge.mov", volume: usb, fileSize: 3 * 1024 * 1024 * 1024) == .reference)
        #expect(copying.decide(path: "/Users/me/a.mov", volume: VolumeTraits(), fileSize: 10) == .reference)
    }
}

@Suite("FileNaming")
struct FileNamingTests {
    @Test("Names are sanitized into one safe path component")
    func sanitize() {
        #expect(FileNaming.sanitized("a/b:c.txt") == "a-b-c.txt")
        #expect(FileNaming.sanitized("  ..hidden  ") == "hidden")
        #expect(FileNaming.sanitized("   ") == "Untitled")
        #expect(FileNaming.sanitized("line one\nline two") == "line one line two")
        let long = String(repeating: "x", count: 300) + ".txt"
        let sanitized = FileNaming.sanitized(long)
        #expect(sanitized.count == 200)
        #expect(sanitized.hasSuffix(".txt"))
    }

    @Test("Unique names count up")
    func unique() {
        #expect(FileNaming.unique("a.txt", existing: []) == "a.txt")
        #expect(FileNaming.unique("a.txt", existing: ["a.txt", "a 2.txt"]) == "a 3.txt")
        #expect(FileNaming.unique("folder", existing: ["folder"]) == "folder 2")
    }

    @Test("Timestamped names match the screenshot style")
    func timestamped() throws {
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let name = try FileNaming.timestamped("Image", date: date, extension: "png", timeZone: #require(TimeZone(identifier: "UTC")))
        #expect(name == "Image 2026-09-21 at 14.13.20.png")
    }
}
