import AppKit
import MyinkCore
import SwiftUI

/// Everything Settings needs from the rest of the app, injected as closures so this module depends on nothing but
/// SettingsStore and MyinkCore.
struct SettingsActions {
    var isLaunchAtLoginEnabled: () -> Bool
    var setLaunchAtLogin: (Bool) -> Void
    /// Extra text under the login toggle, e.g. "Needs approval in System Settings → General → Login Items" or
    /// "Run the installed copy in ~/Applications to enable". nil = nothing.
    var loginItemNote: () -> String?
    var openLoginItemsSettings: () -> Void
    var isPDFServiceInstalled: () -> Bool
    var setPDFServiceInstalled: (Bool) -> Void
    var openKeyboardShortcutsSettings: () -> Void
    /// Bytes stored under ~/Library/Application Support/Myink/Items (may be slow — call off the main actor or in a .task).
    var storageUsage: @Sendable () async -> Int64
    var recentlyRemovedCount: () -> Int
    var emptyRecentlyRemoved: () -> Void
    /// The hotkey recorder view (provided by the hotkey module): (combo binding, enabled binding) -> view.
    var shortcutRecorder: (Binding<KeyCombo>, Binding<Bool>) -> AnyView
    /// True when the chosen shortcut could not be registered (taken by another app).
    var hotKeyRegistrationFailed: () -> Bool
}

/// The "Myink Settings" window: SwiftUI panes hosted in a plain AppKit window.
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private static let autosaveName = "MyinkSettings"
    private var hasBeenShown = false
    private let hasSavedFrame: Bool

    init(settings: SettingsStore, actions: SettingsActions) {
        let hosting = NSHostingController(rootView: SettingsView(settings: settings, actions: actions))
        hosting.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.title = "Myink Settings"
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        hasSavedFrame = window.setFrameUsingName(Self.autosaveName)
        window.setFrameAutosaveName(Self.autosaveName)
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Shows the window (centered the first time), activating Myink since it runs as an accessory app.
    func show() {
        guard let window else { return }
        if !hasBeenShown, !hasSavedFrame {
            window.center()
        }
        hasBeenShown = true
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        Log.app.info("Settings window shown")
    }

    func windowWillClose(_: Notification) {
        Log.app.debug("Settings window closed")
    }
}
