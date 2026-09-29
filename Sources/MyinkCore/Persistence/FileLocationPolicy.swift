import Foundation

/// What we know about the volume a dropped file lives on.
public struct VolumeTraits: Sendable, Equatable {
    public var isRemovable: Bool
    public var isEjectable: Bool
    public var isLocal: Bool

    public init(isRemovable: Bool = false, isEjectable: Bool = false, isLocal: Bool = true) {
        self.isRemovable = isRemovable
        self.isEjectable = isEjectable
        self.isLocal = isLocal
    }

    /// Removable, ejectable (external drives, disk images) or network volumes.
    public var isExternal: Bool {
        isRemovable || isEjectable || !isLocal
    }

    public static func of(_ url: URL) -> VolumeTraits? {
        guard let values = try? url.resourceValues(forKeys: [.volumeIsRemovableKey, .volumeIsEjectableKey, .volumeIsLocalKey])
        else { return nil }
        return VolumeTraits(
            isRemovable: values.volumeIsRemovable ?? false,
            isEjectable: values.volumeIsEjectable ?? false,
            isLocal: values.volumeIsLocal ?? true
        )
    }
}

/// Decides whether a dropped file is kept by reference (the default, like Yoink) or copied into
/// Myink's storage because its location is transient or private to another app.
public struct FileLocationPolicy: Sendable, Equatable {
    public enum Decision: Sendable, Equatable {
        case reference
        case copy(OwnedFile.Origin)
    }

    public var homeDirectory: String
    public var temporaryDirectory: String
    public var itemsRoot: String
    public var copyFromExternalVolumes: Bool
    public var externalCopyLimit: Int64

    public init(
        homeDirectory: String = NSHomeDirectory(),
        temporaryDirectory: String = NSTemporaryDirectory(),
        itemsRoot: String,
        copyFromExternalVolumes: Bool = false,
        externalCopyLimit: Int64 = 2 * 1024 * 1024 * 1024
    ) {
        self.homeDirectory = Self.trimmed(homeDirectory)
        self.temporaryDirectory = Self.trimmed(temporaryDirectory)
        self.itemsRoot = Self.trimmed(itemsRoot)
        self.copyFromExternalVolumes = copyFromExternalVolumes
        self.externalCopyLimit = externalCopyLimit
    }

    public func decide(path: String, volume: VolumeTraits?, fileSize: Int64?) -> Decision {
        if isInside(path, itemsRoot) || isTransient(path) || isAppPrivate(path) || path.contains(".photoslibrary/") {
            return .copy(.copy)
        }
        if copyFromExternalVolumes, volume?.isExternal == true, (fileSize ?? 0) <= externalCopyLimit {
            return .copy(.volumeCopy)
        }
        return .reference
    }

    /// Temporary locations: the per-user temp folders, /tmp and "TemporaryItems" folders
    /// (screenshot thumbnails, print-to-PDF output, drags from apps that export on the fly).
    func isTransient(_ path: String) -> Bool {
        let roots = ["/private/var/folders", "/var/folders", "/private/tmp", "/tmp", temporaryDirectory]
        return roots.contains { isInside(path, $0) } || path.contains("/TemporaryItems/")
    }

    /// Anything under ~/Library except iCloud Drive and File Provider storage belongs to some app
    /// (Mail downloads, containers, caches) and may vanish, so it's copied.
    func isAppPrivate(_ path: String) -> Bool {
        let library = homeDirectory + "/Library"
        guard isInside(path, library) else { return false }
        return !isInside(path, library + "/Mobile Documents") && !isInside(path, library + "/CloudStorage")
    }

    private func isInside(_ path: String, _ root: String) -> Bool {
        guard !root.isEmpty else { return false }
        return path.hasPrefix(root + "/")
    }

    private static func trimmed(_ path: String) -> String {
        path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}
