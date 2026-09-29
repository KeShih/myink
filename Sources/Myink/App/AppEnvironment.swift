import AppKit
import MyinkCore
import SwiftUI

/// Composition root: builds every subsystem, wires them together and answers automation requests.
final class AppEnvironment: NSObject, AutomationTarget {
    let settings = SettingsStore()
    let store: ShelfStore
    let importer: ImportCoordinator
    let shelfViewController: ShelfViewController
    let shelf: ShelfWindowController
    private let dragMonitor = DragMonitor()
    private let hotKey = HotKeyController()
    private let statusItem = StatusItemController()
    private let activationPolicy = ActivationPolicyController()
    private let loginItem = LoginItemController()
    private var servicesProvider: ServicesProvider?
    private var urlRouter: URLCommandRouter?
    private var settingsWindow: SettingsWindowController?
    private var termination: TerminationHandler?
    private var pendingURLs: [URL] = []
    private var isStarted = false

    override init() {
        store = ShelfStore()
        importer = ImportCoordinator(store: store, settings: settings)
        shelfViewController = ShelfViewController(store: store, settings: settings, importer: importer)
        shelf = ShelfWindowController(settings: settings, store: store, viewController: shelfViewController)
        super.init()
        store.preferences = { [settings] in settings.preferences }
        servicesProvider = ServicesProvider(target: self)
        urlRouter = URLCommandRouter(target: self)
        AutomationRouting.target = self
    }

    func start() {
        store.performMaintenance()
        PreviewMaterializer(store: store).purge()
        store.observe { [weak self] in self?.storeChanged() }
        settings.observe { [weak self] old, new in self?.preferencesChanged(from: old, to: new) }

        shelfViewController.appMenuProvider = { [weak self] in self?.makeAppMenu() ?? NSMenu() }

        let preferences = settings.preferences
        statusItem.isVisible = preferences.showInMenuBar
        statusItem.onClick = { [weak self] in self?.shelf.send(.toggle) }
        statusItem.menuProvider = { [weak self] in self?.makeAppMenu() ?? NSMenu() }
        statusItem.performDrop = { [weak self] info in self?.dropOnIcon(info) ?? false }
        activationPolicy.apply(showInDock: preferences.showInDock)

        hotKey.onTap = { [weak self] in self?.shelf.send(.toggle) }
        hotKey.onLongPress = { [weak self] in self?.shelf.send(.longPress) }
        hotKey.update(preferences.hotKeyEnabled ? preferences.hotKey : nil)

        dragMonitor.onEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case let .began(session): shelf.dragBegan(session)
            case let .moved(point, time): shelf.dragMoved(to: point, at: time)
            case .ended: shelf.dragEnded()
            }
        }
        dragMonitor.start()

        NSApp.servicesProvider = servicesProvider
        registerServicesIfNeeded()
        termination = TerminationHandler { [weak self] in self?.store.flush() }

        shelf.start()
        store.refreshAvailability()
        isStarted = true
        let queued = pendingURLs
        pendingURLs = []
        open(queued)
        Log.app.info("Myink started (\(self.store.state.itemCount) items on the shelf)")
    }

    // MARK: Open events (Dock drops, open -a, Open With, PDF Services, myink:// URLs)

    func open(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        guard isStarted else {
            pendingURLs += urls
            return
        }
        let commands = urls.filter { $0.scheme?.lowercased() == MyinkURLCommand.scheme }
        let files = urls.filter(\.isFileURL)
        for url in commands {
            urlRouter?.handle(url)
        }
        if !files.isEmpty {
            addFiles(files, asStack: nil, reveal: true)
        }
    }

    /// Dock icon clicked (or app relaunched from Finder/Spotlight).
    func handleReopen() {
        if settings.preferences.showInDock {
            shelf.send(.toggle)
        } else {
            openSettings()
        }
    }

    // MARK: Changes

    private func storeChanged() {
        shelfViewController.reload(animated: true)
        shelf.storeChanged()
    }

    private func preferencesChanged(from old: Preferences, to new: Preferences) {
        shelf.preferencesChanged(from: old, to: new)
        if old.showInMenuBar != new.showInMenuBar { statusItem.isVisible = new.showInMenuBar }
        if old.showInDock != new.showInDock { activationPolicy.apply(showInDock: new.showInDock) }
        if old.hotKey != new.hotKey || old.hotKeyEnabled != new.hotKeyEnabled {
            hotKey.update(new.hotKeyEnabled ? new.hotKey : nil)
        }
        if old.recentlyRemovedLimit != new.recentlyRemovedLimit || old.recentlyRemovedDays != new.recentlyRemovedDays {
            store.pruneRecentlyRemoved()
        }
        if new.autoRemoveMissing, !old.autoRemoveMissing {
            store.refreshAvailability()
        }
    }

    private func dropOnIcon(_ info: any NSDraggingInfo) -> Bool {
        let added = importer.importPasteboard(info.draggingPasteboard, at: 0, allowPromises: true)
        if added > 0 { announceAdded(reveal: true) }
        return added > 0
    }

    private func announceAdded(reveal: Bool) {
        statusItem.flash()
        if reveal { shelf.send(.itemsAddedExternally) }
    }

    /// Re-registers Services after an update so new/changed services show up.
    private func registerServicesIfNeeded() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        let key = "servicesRegisteredForVersion"
        guard UserDefaults.standard.string(forKey: key) != version else { return }
        NSUpdateDynamicServices()
        UserDefaults.standard.set(version, forKey: key)
    }

    // MARK: Menu (menu bar icon and the shelf's ⋯ button)

    func makeAppMenu() -> NSMenu {
        let menu = NSMenu()
        let state = store.state
        let toggleTitle = shelf.isVisible ? "Hide Shelf" : "Show Shelf"
        let toggle = ClosureMenuItem(toggleTitle) { [weak self] in self?.shelf.send(.toggle) }
        if settings.preferences.hotKeyEnabled {
            toggle.toolTip = "Shortcut: \(KeyNameTranslator.display(settings.preferences.hotKey))"
        }
        menu.addItem(toggle)
        menu.addItem(.separator())

        let recent = NSMenuItem(title: "Recently Removed", action: nil, keyEquivalent: "")
        let recentMenu = NSMenu()
        if state.recentlyRemoved.isEmpty {
            recentMenu.addItem(NSMenuItem(title: "Nothing Removed Recently", action: nil, keyEquivalent: ""))
        } else {
            recentMenu.addItem(ClosureMenuItem("Restore Last Removed") { [weak self] in _ = self?.restoreRemoved() })
            recentMenu.addItem(.separator())
            for removed in state.recentlyRemoved.prefix(12) {
                let entry = removed.entry
                let title = entry.isStack ? "\(entry.items.count) Items" : entry.items.first?.displayName ?? "Item"
                let item = ClosureMenuItem(title) { [weak self] in
                    guard let self, !store.restore([removed.id]).isEmpty else { return }
                    shelf.send(.itemsAddedExternally)
                }
                item.toolTip = removed.removedAt.formatted(date: .abbreviated, time: .shortened)
                recentMenu.addItem(item)
            }
            recentMenu.addItem(.separator())
            recentMenu.addItem(ClosureMenuItem("Empty Recently Removed") { [weak self] in self?.store.emptyRecentlyRemoved() })
        }
        recent.submenu = recentMenu
        menu.addItem(recent)

        if !state.entries.isEmpty {
            let allLocked = state.entries.allSatisfy(\.isLocked)
            menu
                .addItem(ClosureMenuItem(allLocked ? "Unlock All" : "Lock All") { [weak self] in
                    self?.store.mutate { $0.toggleAllLocks() }
                })
            if !store.unavailableItemIDs.isEmpty {
                menu.addItem(ClosureMenuItem("Remove Missing Items") { [weak self] in self?.shelfViewController.removeMissing() })
            }
            menu.addItem(ClosureMenuItem("Clear Shelf") { [weak self] in _ = self?.clearShelf(includingLocked: false) })
            let clearAll = ClosureMenuItem("Clear Shelf Including Locked") { [weak self] in _ = self?.clearShelf(includingLocked: true) }
            clearAll.isAlternate = true
            clearAll.keyEquivalentModifierMask = .option
            menu.addItem(clearAll)
        }
        menu.addItem(.separator())
        let autoShow = ClosureMenuItem("Show Shelf While Dragging") { [weak self] in
            self?.settings.preferences.autoShowEnabled.toggle()
        }
        autoShow.state = settings.preferences.autoShowEnabled ? .on : .off
        menu.addItem(autoShow)
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Settings…", key: ",") { [weak self] in self?.openSettings() })
        menu.addItem(ClosureMenuItem("Quit Myink", key: "q") { NSApp.terminate(nil) })
        return menu
    }

    // MARK: Settings

    func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(settings: settings, actions: makeSettingsActions())
        }
        settingsWindow?.show()
    }

    private func makeSettingsActions() -> SettingsActions {
        let files = store.files
        return SettingsActions(
            isLaunchAtLoginEnabled: { [loginItem] in loginItem.isEnabled },
            setLaunchAtLogin: { [loginItem] enabled in
                do {
                    try loginItem.setEnabled(enabled)
                } catch {
                    NSAlert(error: error).runModal()
                }
            },
            loginItemNote: { [loginItem] in loginItem.note },
            openLoginItemsSettings: { [loginItem] in loginItem.openSystemSettings() },
            isPDFServiceInstalled: { PDFServiceInstaller.isInstalled() },
            setPDFServiceInstalled: { install in
                do {
                    if install { try PDFServiceInstaller.install() } else { try PDFServiceInstaller.uninstall() }
                } catch {
                    NSAlert(error: error).runModal()
                }
            },
            openKeyboardShortcutsSettings: {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            },
            storageUsage: { await Task.detached { files.totalSize() }.value },
            recentlyRemovedCount: { [store] in store.state.recentlyRemoved.count },
            emptyRecentlyRemoved: { [store] in store.emptyRecentlyRemoved() },
            shortcutRecorder: { [hotKey] combo, enabled in
                AnyView(ShortcutRecorder(combo: combo, isEnabled: enabled, onRecordingChanged: { recording in
                    hotKey.isSuspended = recording
                }))
            },
            hotKeyRegistrationFailed: { [hotKey] in hotKey.registrationFailed }
        )
    }

    // MARK: AutomationTarget

    @discardableResult
    func addFiles(_ urls: [URL], asStack: Bool?, reveal: Bool) -> Int {
        let added = importer.importFiles(urls, asStack: asStack)
        if added > 0 { announceAdded(reveal: reveal) }
        return added
    }

    @discardableResult
    func addText(_ text: String, reveal: Bool) -> Int {
        let added = importer.importText(text)
        if added > 0 { announceAdded(reveal: reveal) }
        return added
    }

    @discardableResult
    func addLink(_ url: String, title: String?, reveal: Bool) -> Int {
        let added = importer.importLink(url, title: title)
        if added > 0 { announceAdded(reveal: reveal) }
        return added
    }

    @discardableResult
    func addPasteboard(_ pasteboard: NSPasteboard, reveal: Bool) -> Int {
        let added = importer.importPasteboard(pasteboard, at: 0)
        if added > 0 { announceAdded(reveal: reveal) }
        return added
    }

    func showShelf() {
        shelf.send(.show)
    }

    func hideShelf() {
        shelf.send(.hide)
    }

    func toggleShelf() {
        shelf.send(.toggle)
    }

    @discardableResult
    func clearShelf(includingLocked: Bool) -> Int {
        store.clear(includingLocked: includingLocked)
    }

    @discardableResult
    func restoreRemoved() -> Int {
        let before = store.state.itemCount
        let restored = store.restoreLatestBatch()
        if !restored.isEmpty { shelf.send(.itemsAddedExternally) }
        return store.state.itemCount - before
    }

    var itemCount: Int {
        store.state.itemCount
    }
}
