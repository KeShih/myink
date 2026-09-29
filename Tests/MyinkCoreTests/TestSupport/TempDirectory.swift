import Foundation

/// A unique scratch directory that is deleted when the value goes away.
final class TempDirectory: @unchecked Sendable {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "MyinkTests-\(UUID().uuidString)", directoryHint: .isDirectory)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    @discardableResult
    func file(_ relativePath: String, contents: String = "hello") throws -> URL {
        let fileURL = url.appending(path: relativePath, directoryHint: .notDirectory)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: fileURL)
        return fileURL
    }

    func directory(_ relativePath: String) throws -> URL {
        let directoryURL = url.appending(path: relativePath, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }
}
