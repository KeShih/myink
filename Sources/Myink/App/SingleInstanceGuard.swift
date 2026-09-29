import AppKit

/// Keeps a single Myink running: a second launch hands focus to the first and quits.
enum SingleInstanceGuard {
    /// Returns false if another Myink (same bundle id, different pid) is already running — after
    /// activating it. Call early in `applicationWillFinishLaunching`; the caller terminates.
    static func claim() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return true }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != ownPID && !$0.isTerminated }
        guard let other = others.first else { return true }
        Log.app.notice("Another Myink is running (pid \(other.processIdentifier)); deferring to it")
        other.activate()
        return false
    }
}
