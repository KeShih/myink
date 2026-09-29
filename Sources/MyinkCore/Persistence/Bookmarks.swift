import Foundation

/// Bookmarks let Myink follow referenced files when they're moved or renamed. Myink isn't
/// sandboxed, so these are plain (not security-scoped) bookmarks.
public enum Bookmarks {
    public struct Resolution: Sendable, Equatable {
        /// Where the file is now (nil if it can't be found).
        public var url: URL?
        /// The bookmark should be recreated (the file moved or its volume changed).
        public var isStale: Bool
        public var availability: Availability
    }

    public static func create(for url: URL) throws -> Data {
        try url.bookmarkData(options: [], includingResourceValuesForKeys: [.volumeURLKey], relativeTo: nil)
    }

    /// Resolves a bookmark without UI and without mounting volumes, classifying the result.
    public static func resolve(_ bookmark: Data, lastKnownPath: String, homeDirectory: String = NSHomeDirectory()) -> Resolution {
        var stale = false
        if let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withoutUI, .withoutMounting],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ),
            FileManager.default.fileExists(atPath: url.path) {
            let resolvedPath = url.resolvingSymlinksInPath().path
            let resolvedHome = URL(filePath: homeDirectory).resolvingSymlinksInPath().path
            let trashed = isInTrash(path: resolvedPath, homeDirectory: resolvedHome) || isInTrash(
                path: url.path,
                homeDirectory: homeDirectory
            )
            let availability: Availability = trashed ? .inTrash : .available
            return Resolution(url: url, isStale: stale || url.path != lastKnownPath, availability: availability)
        }
        return Resolution(
            url: nil,
            isStale: false,
            availability: volumeIsOffline(bookmark: bookmark, lastKnownPath: lastKnownPath) ? .offline : .missing
        )
    }

    public static func isInTrash(path: String, homeDirectory: String = NSHomeDirectory()) -> Bool {
        let home = homeDirectory.hasSuffix("/") ? String(homeDirectory.dropLast()) : homeDirectory
        return path.hasPrefix(home + "/.Trash/") || path.contains("/.Trashes/")
    }

    /// True when the file lived on a volume that isn't mounted right now.
    static func volumeIsOffline(bookmark: Data, lastKnownPath: String) -> Bool {
        if let values = URL.resourceValues(forKeys: [.volumeURLKey], fromBookmarkData: bookmark), let volume = values.volume {
            return !FileManager.default.fileExists(atPath: volume.path)
        }
        return volumeRoot(of: lastKnownPath).map { !FileManager.default.fileExists(atPath: $0) } ?? false
    }

    /// `/Volumes/Name` for paths on external volumes, nil for the boot volume.
    static func volumeRoot(of path: String) -> String? {
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        guard components.count >= 2, components[0] == "Volumes" else { return nil }
        return "/Volumes/\(components[1])"
    }
}
