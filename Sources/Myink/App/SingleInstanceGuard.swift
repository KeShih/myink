import AppKit

/// Keeps a single Myink running: a newer launch hands its work to the first copy and quits.
enum SingleInstanceGuard {
    /// The already-running copy this process should defer to, or nil if this process is the one to
    /// keep. Only the newer of two copies yields (so two simultaneous launches can't both quit).
    static func existingInstance() -> NSRunningApplication? {
        guard let bundleID = Bundle.main.bundleIdentifier else { return nil }
        let own = NSRunningApplication.current
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != own.processIdentifier && !$0.isTerminated }
        return others.first { other in
            switch (other.launchDate, own.launchDate) {
            case let (theirs?, ours?) where theirs != ours: theirs < ours
            default: other.processIdentifier < own.processIdentifier
            }
        }
    }

    /// Sends files and myink:// URLs this copy received to the running copy.
    static func forward(_ urls: [URL], to other: NSRunningApplication) {
        guard !urls.isEmpty, let appURL = other.bundleURL else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: configuration)
        Log.app.notice("forwarded \(urls.count) item(s) to the running Myink")
    }
}
