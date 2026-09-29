import Foundation

/// The on-disk format of the shelf.
public struct Manifest: Codable, Sendable, Equatable {
    public static let currentVersion = 1

    public var version: Int
    public var state: ShelfState

    public init(version: Int = Manifest.currentVersion, state: ShelfState) {
        self.version = version
        self.state = state
    }
}

public enum ManifestLoadResult: Sendable, Equatable {
    /// The manifest was read normally.
    case loaded(ShelfState)
    /// The manifest was missing or unreadable and the backup was used. An unreadable manifest is
    /// moved aside (never deleted) to `quarantined`.
    case recovered(ShelfState, quarantined: URL?)
    /// Nothing usable was found; start with an empty shelf.
    case fresh(quarantined: URL?)

    public var state: ShelfState {
        switch self {
        case let .loaded(state), let .recovered(state, _): state
        case .fresh: ShelfState()
        }
    }
}

/// Reads and writes `shelf.json`. Writes are atomic; a successful launch-time load refreshes the
/// backup, and an unreadable manifest is quarantined rather than overwritten.
public struct ManifestStore: Sendable {
    public let layout: StorageLayout

    public init(layout: StorageLayout) {
        self.layout = layout
    }

    public func load() -> ManifestLoadResult {
        let fileManager = FileManager.default
        var quarantined: URL?
        if fileManager.fileExists(atPath: layout.manifestURL.path) {
            if let state = try? decode(layout.manifestURL) {
                return .loaded(state)
            }
            quarantined = quarantine(layout.manifestURL)
        }
        if fileManager.fileExists(atPath: layout.backupURL.path), let state = try? decode(layout.backupURL) {
            return .recovered(state, quarantined: quarantined)
        }
        return .fresh(quarantined: quarantined)
    }

    public func save(_ state: ShelfState) throws {
        try layout.createDirectories()
        let data = try Self.encoder.encode(Manifest(state: state.persistable))
        try data.write(to: layout.manifestURL, options: .atomic)
    }

    /// Copies the current manifest to the backup (call after a successful load).
    public func refreshBackup() {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: layout.manifestURL.path) else { return }
        try? fileManager.removeItem(at: layout.backupURL)
        try? fileManager.copyItem(at: layout.manifestURL, to: layout.backupURL)
    }

    private func decode(_ url: URL) throws -> ShelfState {
        let manifest = try Self.decoder.decode(Manifest.self, from: Data(contentsOf: url))
        guard manifest.version <= Manifest.currentVersion else { throw CocoaError(.fileReadCorruptFile) }
        return manifest.state
    }

    private func quarantine(_ url: URL) -> URL? {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let destination = url.deletingLastPathComponent().appending(path: "shelf.corrupt-\(stamp).json")
        do {
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        } catch {
            return nil
        }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder // default date encoding round-trips exactly
    }

    private static var decoder: JSONDecoder {
        JSONDecoder()
    }
}
