import Foundation

/// Where Myink keeps its data:
///
///     <root>/shelf.json        the manifest (ShelfState)
///     <root>/shelf.json.bak    last known-good manifest
///     <root>/Items/<dir>/…     files Myink owns and snippet data
public struct StorageLayout: Sendable, Equatable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// `~/Library/Application Support/Myink`.
    public static func applicationSupport(appName: String = "Myink") -> StorageLayout {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(filePath: NSHomeDirectory()).appending(path: "Library/Application Support", directoryHint: .isDirectory)
        return StorageLayout(root: base.appending(path: appName, directoryHint: .isDirectory))
    }

    public var manifestURL: URL {
        root.appending(path: "shelf.json", directoryHint: .notDirectory)
    }

    public var backupURL: URL {
        root.appending(path: "shelf.json.bak", directoryHint: .notDirectory)
    }

    public var itemsRoot: URL {
        root.appending(path: "Items", directoryHint: .isDirectory)
    }

    public func url(forOwnedPath relativePath: String) -> URL {
        itemsRoot.appending(path: relativePath, directoryHint: .inferFromPath)
    }

    public func createDirectories() throws {
        try FileManager.default.createDirectory(at: itemsRoot, withIntermediateDirectories: true)
    }
}
