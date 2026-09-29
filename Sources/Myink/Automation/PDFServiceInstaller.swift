import Foundation

/// Manages "Save PDF to Myink" in the print dialog's PDF menu: a Finder alias to the app in
/// `~/Library/PDF Services`. macOS opens the printed PDF (a temporary file) with the app, so it
/// arrives through `application(_:open:)` like any other opened file.
nonisolated enum PDFServiceInstaller {
    static let menuTitle = "Save PDF to Myink"

    /// `~/Library/PDF Services/Save PDF to Myink`
    static var aliasURL: URL {
        URL.homeDirectory.appending(path: "Library/PDF Services", directoryHint: .isDirectory)
            .appending(path: menuTitle, directoryHint: .notDirectory)
    }

    static func isInstalled() -> Bool {
        FileManager.default.fileExists(atPath: aliasURL.path(percentEncoded: false))
    }

    /// Creates ~/Library/PDF Services if needed and writes a Finder alias to the app (replacing an old one).
    static func install(appURL: URL = Bundle.main.bundleURL) throws {
        try FileManager.default.createDirectory(at: aliasURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let bookmark = try appURL.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
        try uninstall()
        try URL.writeBookmarkData(bookmark, to: aliasURL)
        Log.automation.info("installed PDF service alias to \(appURL.path(percentEncoded: false), privacy: .public)")
    }

    static func uninstall() throws {
        guard isInstalled() else { return }
        try FileManager.default.removeItem(at: aliasURL)
        Log.automation.info("removed PDF service alias")
    }
}
