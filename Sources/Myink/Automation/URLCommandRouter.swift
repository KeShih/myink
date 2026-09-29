import AppKit
import MyinkCore

/// Performs `myink://` URLs (see `MyinkURLCommand`). URLs can come from web pages, so bad ones are
/// only logged — never beeped at or shown.
final class URLCommandRouter {
    private weak var target: (any AutomationTarget)?

    init(target: any AutomationTarget) {
        self.target = target
    }

    /// Handles a myink:// URL. Returns false (and logs) for malformed/unknown commands.
    @discardableResult func handle(_ url: URL) -> Bool {
        let command: MyinkURLCommand
        switch MyinkURLCommand.parse(url) {
        case let .success(parsed): command = parsed
        case let .failure(error):
            Log.automation.error("ignoring URL \(url.absoluteString, privacy: .public): \(String(describing: error), privacy: .public)")
            return false
        }
        guard let target else {
            Log.automation.error("no automation target for \(url.absoluteString, privacy: .public)")
            return false
        }
        Log.automation.info("URL command: \(String(describing: command))")

        switch command {
        case let .addPaths(paths, asStack, reveal):
            var urls: [URL] = []
            for path in paths {
                if FileManager.default.fileExists(atPath: path) {
                    urls.append(URL(fileURLWithPath: path))
                } else {
                    Log.automation.error("add: skipping missing path \(path, privacy: .public)")
                }
            }
            guard !urls.isEmpty else { return false }
            target.addFiles(urls, asStack: asStack, reveal: reveal)
        case let .addURL(link, title, reveal): target.addLink(link, title: title, reveal: reveal)
        case let .addText(text, reveal): target.addText(text, reveal: reveal)
        case .show: target.showShelf()
        case .hide: target.hideShelf()
        case .toggle: target.toggleShelf()
        case let .clear(includingLocked): target.clearShelf(includingLocked: includingLocked)
        case .restore: target.restoreRemoved()
        case .settings: target.openSettings()
        case .quit: NSApp.terminate(nil)
        }
        return true
    }
}
