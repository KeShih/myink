import AppKit
import MyinkCore

/// Turns pasteboards, files and snippets into shelf entries. Shared by every entry point: drops on
/// the shelf, the menu bar icon and the Dock icon, Services, `open -a`, the URL scheme and AppleScript.
///
/// Fast work (bookmarks, small snippets) happens immediately; copies, large payloads and file promises
/// get a placeholder that is completed asynchronously.
final class ImportCoordinator {
    private let store: ShelfStore
    private let settings: SettingsStore
    private let promiseQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "dev.keshi.myink.promises"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 2
        return queue
    }()

    /// Payloads up to this size are stored synchronously.
    private let synchronousLimit = 1 << 20
    private let promiseTimeout: Duration = .seconds(120)

    /// Called with the entry that already holds a dropped file (to highlight it instead of adding a duplicate).
    var onDuplicate: ((UUID) -> Void)?

    init(store: ShelfStore, settings: SettingsStore) {
        self.store = store
        self.settings = settings
    }

    private enum Build {
        case ready(ShelfItem)
        case deferred(placeholder: ShelfItem, work: @Sendable (UUID) async throws -> ShelfItem?)
        case promise(placeholder: ShelfItem, receiver: NSFilePromiseReceiver)

        var item: ShelfItem {
            switch self {
            case let .ready(item), let .deferred(item, _), let .promise(item, _): item
            }
        }
    }

    // MARK: Entry points

    /// Imports every item of a pasteboard (a drop, a Services request, ⌘V…). File promises are only
    /// honoured for drag pasteboards. Returns the number of items added.
    @discardableResult
    func importPasteboard(_ pasteboard: NSPasteboard, at index: Int? = nil, asStack: Bool? = nil, allowPromises: Bool = false) -> Int {
        let pasteboardItems = pasteboard.pasteboardItems ?? []
        let promiseTypes = Set(TypeCatalog.promiseTypes)
        let promiseCapable = pasteboardItems.indices.filter { index in
            pasteboardItems[index].types.contains { promiseTypes.contains($0.rawValue) }
        }
        var receivers: [NSFilePromiseReceiver] = []
        if allowPromises, !promiseCapable.isEmpty {
            receivers = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver] ?? []
        }

        var builds: [Build] = []
        for (position, pasteboardItem) in pasteboardItems.enumerated() {
            if let url = Self.fileURL(of: pasteboardItem) {
                if let build = build(forFile: url) { builds.append(build) }
                continue
            }
            if allowPromises, let slot = promiseCapable.firstIndex(of: position), slot < receivers.count {
                builds.append(build(forPromise: receivers[slot]))
                continue
            }
            let snapshot = PasteboardSnapshot.capture(pasteboardItem)
            if let build = build(for: ImportClassifier.classify(snapshot)) { builds.append(build) }
        }
        return add(builds, at: index, asStack: asStack)
    }

    /// Imports files and folders (open events, Services, URL scheme, AppleScript).
    @discardableResult
    func importFiles(_ urls: [URL], at index: Int? = nil, asStack: Bool? = nil) -> Int {
        add(urls.compactMap(build(forFile:)), at: index, asStack: asStack)
    }

    @discardableResult
    func importText(_ text: String) -> Int {
        let representation = CapturedRepresentation(type: TypeCatalog.plainText, data: Data(text.utf8))
        let candidate = ImportCandidate.text(representations: [representation], preview: text)
        return add([build(for: candidate)].compactMap(\.self), at: nil, asStack: false)
    }

    @discardableResult
    func importLink(_ url: String, title: String?) -> Int {
        var representations = [CapturedRepresentation(type: TypeCatalog.url, data: Data(url.utf8))]
        if let title { representations.append(CapturedRepresentation(type: TypeCatalog.urlName, data: Data(title.utf8))) }
        let candidate = ImportCandidate.link(url: url, title: title, representations: representations)
        return add([build(for: candidate)].compactMap(\.self), at: nil, asStack: false)
    }

    // MARK: Building items

    private func build(forFile rawURL: URL) -> Build? {
        let url = ((rawURL as NSURL).filePathURL ?? rawURL).standardizedFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            Log.importer.error("dropped file doesn't exist: \(url.path, privacy: .public)")
            return nil
        }
        if let existing = store.state.entryReferencing(path: url.path) {
            onDuplicate?(existing.id)
            return nil
        }
        let policy = FileLocationPolicy(
            itemsRoot: store.layout.itemsRoot.path,
            copyFromExternalVolumes: settings.preferences.copyFromExternalVolumes
        )
        let size = (try? url.resourceValues(forKeys: [.totalFileSizeKey]))?.totalFileSize.map(Int64.init)
        switch policy.decide(path: url.path, volume: VolumeTraits.of(url), fileSize: size) {
        case .reference:
            do {
                return .ready(try store.factory.reference(to: url))
            } catch {
                Log.importer.error("couldn't reference \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return nil
            }
        case let .copy(origin):
            let factory = store.factory
            let placeholder = Self.placeholder(named: url.lastPathComponent, kind: .copying)
            return .deferred(placeholder: placeholder) { id in
                try await factory.copy(url, origin: origin, id: id)
            }
        }
    }

    private func build(forPromise receiver: NSFilePromiseReceiver) -> Build {
        let name = receiver.fileNames.first ?? "Receiving…"
        return .promise(placeholder: Self.placeholder(named: name, kind: .receiving), receiver: receiver)
    }

    private func build(for candidate: ImportCandidate) -> Build? {
        switch candidate {
        case .nothing:
            return nil
        case let .fileURL(url):
            return build(forFile: url)
        default:
            let factory = store.factory
            if candidate.payloadSize <= synchronousLimit {
                do {
                    return try factory.makeNow(candidate).map(Build.ready)
                } catch {
                    Log.importer.error("storing pasteboard data failed: \(error.localizedDescription, privacy: .public)")
                    return nil
                }
            }
            return .deferred(placeholder: Self.placeholder(named: "Adding…", kind: .writing)) { id in
                try await factory.make(candidate, id: id)
            }
        }
    }

    private static func placeholder(named name: String, kind: Placeholder.Kind) -> ShelfItem {
        ShelfItem(displayName: name, content: .placeholder(Placeholder(kind: kind)))
    }

    // MARK: Adding

    private func add(_ builds: [Build], at index: Int?, asStack: Bool?) -> Int {
        guard !builds.isEmpty else { return 0 }
        let items = builds.map(\.item)
        let group = (asStack ?? settings.preferences.groupDropsIntoStacks) && items.count > 1
        let entries = group ? [ShelfEntry(items: items)] : items.map { ShelfEntry(items: [$0]) }
        store.add(entries, at: index)
        for build in builds {
            switch build {
            case .ready:
                break
            case let .deferred(placeholder, work):
                complete(placeholder.id, with: work)
            case let .promise(placeholder, receiver):
                receive(receiver, into: placeholder.id)
            }
        }
        Log.importer.info("added \(items.count) item(s) as \(entries.count) entr\(entries.count == 1 ? "y" : "ies")")
        return items.count
    }

    private func complete(_ placeholderID: UUID, with work: @escaping @Sendable (UUID) async throws -> ShelfItem?) {
        Task { [store] in
            do {
                if let item = try await work(placeholderID) {
                    store.complete(placeholder: placeholderID, with: item)
                } else {
                    store.markFailed(placeholderID)
                }
            } catch {
                Log.importer.error("import failed: \(error.localizedDescription, privacy: .public)")
                store.markFailed(placeholderID)
            }
        }
    }

    // MARK: File promises

    private func receive(_ receiver: NSFilePromiseReceiver, into placeholderID: UUID) {
        let directory: String
        do {
            directory = try store.files.makeDirectory()
        } catch {
            store.markFailed(placeholderID)
            return
        }
        let destination = store.layout.itemsRoot.appending(path: directory, directoryHint: .isDirectory)
        // The reader runs on `promiseQueue`: it must not inherit the main actor (Swift 6 would trap).
        receiver.receivePromisedFiles(atDestination: destination, options: [:], operationQueue: promiseQueue) { @Sendable [weak self] url, error in
            Task { @MainActor in
                self?.promiseDelivered(url: url, error: error, directory: directory, placeholderID: placeholderID)
            }
        }
        Task { [weak self, promiseTimeout] in
            try? await Task.sleep(for: promiseTimeout)
            guard let self, store.state.item(withID: placeholderID)?.isPlaceholder == true else { return }
            Log.importer.error("file promise timed out")
            store.markFailed(placeholderID)
        }
    }

    private func promiseDelivered(url: URL, error: (any Error)?, directory: String, placeholderID: UUID) {
        if let error {
            Log.importer.error("file promise failed: \(error.localizedDescription, privacy: .public)")
            store.markFailed(placeholderID)
            return
        }
        let relativePath = "\(directory)/\(url.lastPathComponent)"
        if store.state.item(withID: placeholderID)?.isPlaceholder == true {
            store.complete(placeholder: placeholderID, with: store.factory.ownedItem(relativePath: relativePath, origin: .promise, id: placeholderID))
        } else {
            store.append(store.factory.ownedItem(relativePath: relativePath, origin: .promise), besideItem: placeholderID)
        }
    }

    // MARK: Helpers

    private static func fileURL(of item: NSPasteboardItem) -> URL? {
        guard let string = item.string(forType: .fileURL), let url = URL(string: string), url.isFileURL else { return nil }
        return url
    }
}
