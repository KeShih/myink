import AppKit

/// Handles the Services menu entries declared under `NSServices` in Info.plist ("Add to Myink" for
/// files, "Add Selection to Myink" for text, links and images). Install it with
/// `NSApp.servicesProvider = provider` and keep a strong reference. Services arrive on the main thread.
final class ServicesProvider: NSObject {
    private weak var target: (any AutomationTarget)?

    init(target: any AutomationTarget) {
        self.target = target
    }

    @objc func addFilesToShelf(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else {
            Log.automation.error("files service: no file URLs on the pasteboard")
            error.pointee = "Myink couldn't find any files to add."
            return
        }
        guard let target else {
            error.pointee = "Myink isn't ready yet."
            return
        }
        let added = target.addFiles(urls, asStack: nil, reveal: true)
        Log.automation.info("files service: added \(added) item(s) from \(urls.count) file(s)")
        if added == 0 {
            error.pointee = "Myink couldn't add those files."
        }
    }

    @objc func addSelectionToShelf(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let added = target?.addPasteboard(pasteboard, reveal: true) ?? 0
        Log.automation.info("selection service: added \(added) item(s)")
        if added == 0 {
            error.pointee = "Myink couldn't use the selection."
        }
    }
}
