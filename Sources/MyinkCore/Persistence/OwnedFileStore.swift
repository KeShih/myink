import Foundation

/// Manages the files Myink owns under `Items/`. Every import gets its own directory
/// (`Items/<UUID>/`), which keeps names from colliding and makes cleanup a directory delete.
public struct OwnedFileStore: Sendable {
    public let layout: StorageLayout

    public init(layout: StorageLayout) {
        self.layout = layout
    }

    public func url(for relativePath: String) -> URL {
        layout.url(forOwnedPath: relativePath)
    }

    /// Creates a new, empty `Items/<UUID>/` directory and returns its name.
    public func makeDirectory() throws -> String {
        let name = UUID().uuidString
        try FileManager.default.createDirectory(
            at: layout.itemsRoot.appending(path: name, directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        return name
    }

    /// Writes `data` as `fileName` into `directory` (a new directory if nil). Returns the path
    /// relative to the Items directory.
    public func write(_ data: Data, fileName: String, directory: String? = nil) throws -> String {
        let directoryName = try directory ?? makeDirectory()
        let directoryURL = layout.itemsRoot.appending(path: directoryName, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let existing = Set((try? FileManager.default.contentsOfDirectory(atPath: directoryURL.path)) ?? [])
        let name = FileNaming.unique(FileNaming.sanitized(fileName), existing: existing)
        try data.write(to: directoryURL.appending(path: name, directoryHint: .notDirectory), options: .atomic)
        return "\(directoryName)/\(name)"
    }

    /// Copies a file or folder into a new directory (an APFS clone when possible) off the main actor.
    /// Returns the path relative to the Items directory.
    @concurrent
    public func copyIn(_ source: URL, fileName: String? = nil) async throws -> String {
        let directoryName = try makeDirectory()
        let name = FileNaming.sanitized(fileName ?? source.lastPathComponent)
        let destination = layout.itemsRoot.appending(path: directoryName, directoryHint: .isDirectory).appending(path: name)
        do {
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: layout.itemsRoot.appending(path: directoryName, directoryHint: .isDirectory))
            throw error
        }
        return "\(directoryName)/\(name)"
    }

    /// Deletes individual files (relative paths) and then their directories if left empty. Used when
    /// several items share one directory (the files of one file promise).
    public func removeFiles(_ relativePaths: some Sequence<String>) {
        let fileManager = FileManager.default
        for path in relativePaths where !path.isEmpty && !path.split(separator: "/").contains("..") {
            let url = layout.url(forOwnedPath: path)
            try? fileManager.removeItem(at: url)
            let directory = url.deletingLastPathComponent()
            if directory.standardizedFileURL != layout.itemsRoot.standardizedFileURL,
               (try? fileManager.contentsOfDirectory(atPath: directory.path))?.isEmpty == true {
                try? fileManager.removeItem(at: directory)
            }
        }
    }

    /// Deletes whole item directories (by name).
    public func removeDirectories(_ names: some Sequence<String>) {
        for name in names where !name.isEmpty && !name.contains("/") && name != "." && name != ".." {
            try? FileManager.default.removeItem(at: layout.itemsRoot.appending(path: name, directoryHint: .isDirectory))
        }
    }

    /// Deletes directories under Items/ that nothing references and that are older than `minimumAge`
    /// (so imports still in flight are never touched). Returns the deleted names.
    @discardableResult
    public func collectGarbage(referenced: Set<String>, minimumAge: TimeInterval, now: Date = Date()) -> [String] {
        let fileManager = FileManager.default
        guard let names = try? fileManager.contentsOfDirectory(atPath: layout.itemsRoot.path) else { return [] }
        var deleted: [String] = []
        for name in names where !referenced.contains(name) && !name.hasPrefix(".") {
            let url = layout.itemsRoot.appending(path: name, directoryHint: .isDirectory)
            let created = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            guard now.timeIntervalSince(created) >= minimumAge else { continue }
            if (try? fileManager.removeItem(at: url)) != nil {
                deleted.append(name)
            }
        }
        return deleted.sorted()
    }

    /// Total bytes stored under Items/.
    public func totalSize() -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: layout.itemsRoot,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true {
                total += Int64(values?.totalFileAllocatedSize ?? 0)
            }
        }
        return total
    }
}
