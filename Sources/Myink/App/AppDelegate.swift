import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var environment: AppEnvironment?

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard SingleInstanceGuard.claim() else {
            Log.app.info("another Myink is already running; quitting")
            exit(0)
        }
        // Built before launch finishes: open events (Dock drops, `open -a`, URLs) can arrive early.
        environment = AppEnvironment()
        NSApp.mainMenu = MainMenu.make(settingsAction: #selector(openSettings(_:)))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.info("Myink launched from \(Bundle.main.bundlePath, privacy: .public)")
        environment?.start()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
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
