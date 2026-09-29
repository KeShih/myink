import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var environment: AppEnvironment?
    /// Set when another copy was already running: this one forwards its open requests, then quits.
    private var runningInstance: NSRunningApplication?

    func applicationWillFinishLaunching(_ notification: Notification) {
        if let other = SingleInstanceGuard.existingInstance() {
            Log.app.info("another Myink is already running (pid \(other.processIdentifier)); handing over")
            runningInstance = other
            return
        }
        // Built before launch finishes: open events (Dock drops, `open -a`, URLs) can arrive early.
        environment = AppEnvironment()
        NSApp.mainMenu = MainMenu.make(settingsAction: #selector(openSettings(_:)))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if runningInstance != nil {
            // Open events arrive around launch; give them a moment to be forwarded, then quit.
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                exit(0)
            }
            return
        }
        Log.app.info("Myink launched from \(Bundle.main.bundlePath, privacy: .public)")
        environment?.start()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let runningInstance {
            SingleInstanceGuard.forward(urls, to: runningInstance)
            return
        }
        environment?.open(urls)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        environment?.handleReopen()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        environment?.store.flush()
    }

    @objc func openSettings(_ sender: Any?) {
        environment?.openSettings()
    }

    // MARK: AppleScript: the application's "item count" property

    func application(_ sender: NSApplication, delegateHandlesKey key: String) -> Bool {
        key == "itemCount"
    }

    @objc var itemCount: Int {
        environment?.itemCount ?? 0
    }
}
