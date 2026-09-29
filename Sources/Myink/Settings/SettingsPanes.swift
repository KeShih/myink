import AppKit
import MyinkCore
import SwiftUI

/// `@State` resolves to SwiftUI's macro, whose plugin the Command Line Tools lack; spelling the property wrapper
/// through a typealias uses the plain `State` wrapper instead.
private typealias ViewState = State

// MARK: - General

/// Launch at login, menu bar / Dock presence and the global shortcut.
struct GeneralPane: View {
    @Bindable var settings: SettingsStore
    let actions: SettingsActions
    @ViewState private var launchAtLogin: Bool
    /// Bumped whenever Myink becomes active so closure-backed values (login note, hotkey status) re-read.
    @ViewState private var refreshTick = 0

    init(settings: SettingsStore, actions: SettingsActions) {
        self.settings = settings
        self.actions = actions
        _launchAtLogin = State(initialValue: actions.isLaunchAtLoginEnabled())
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { newValue in
                actions.setLaunchAtLogin(newValue)
                launchAtLogin = actions.isLaunchAtLoginEnabled()
                refreshTick += 1
            }
        )
    }

    var body: some View {
        let preferences = settings.preferences
        let _ = refreshTick // swiftlint:disable:this redundant_discardable_let
        Form {
            Section {
                Toggle("Launch Myink at login", isOn: launchAtLoginBinding)
                if let note = actions.loginItemNote() {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(note)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Open Login Items Settings…", action: actions.openLoginItemsSettings)
                    }
                }
            }

            Section {
                Toggle("Show in menu bar", isOn: $settings.preferences.showInMenuBar)
                    .disabled(preferences.showInMenuBar && !preferences.showInDock)
                Toggle("Show in Dock", isOn: $settings.preferences.showInDock)
                    .disabled(preferences.showInDock && !preferences.showInMenuBar)
            } header: {
                Text("Appearance")
            } footer: {
                FootnoteText("Myink needs at least one of these so you can always reach its menu and settings.")
            }

            Section {
                LabeledContent("Show or hide the shelf") {
                    actions.shortcutRecorder($settings.preferences.hotKey, $settings.preferences.hotKeyEnabled)
                }
                if preferences.hotKeyEnabled, actions.hotKeyRegistrationFailed() {
                    Label(
                        "This shortcut is already used by another app. Choose a different one.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.red)
                    .font(.callout)
                }
            } header: {
                Text("Keyboard Shortcut")
            } footer: {
                FootnoteText(
                    "Tap to show or hide the shelf. Hold for a second to bring back the items you removed last. "
                        + "On Apple keyboards, function keys need fn unless 'Use F1, F2, etc. keys as standard "
                        + "function keys' is on."
                )
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            launchAtLogin = actions.isLaunchAtLoginEnabled()
            refreshTick += 1
        }
    }
}

// MARK: - Shelf

/// Where the shelf sits and how it looks.
struct ShelfPane: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        let edge = settings.preferences.edge
        Form {
            Section("Position") {
                Picker("Screen edge", selection: $settings.preferences.edge) {
                    ForEach(ScreenEdge.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Alignment", selection: $settings.preferences.alignment) {
                    ForEach(EdgeAlignment.allCases, id: \.self) { Text($0.title(for: edge)).tag($0) }
                }
                .disabled(settings.preferences.fullLength)
                Toggle("Span the full length of the edge", isOn: $settings.preferences.fullLength)
                Picker("Display", selection: $settings.preferences.screenChoice) {
                    ForEach(ScreenChoice.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }

            Section("Appearance") {
                Picker("Size", selection: $settings.preferences.size) {
                    ForEach(ShelfSize.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("When not in use", selection: $settings.preferences.idlePolicy) {
                    ForEach(VisibilityMachine.IdlePolicy.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Behavior

/// When the shelf appears and what happens to items.
struct BehaviorPane: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        let autoShow = settings.preferences.autoShowEnabled
        Form {
            Section {
                Toggle("Show the shelf automatically while dragging", isOn: $settings.preferences.autoShowEnabled)
                Picker("Show it", selection: $settings.preferences.triggerMode) {
                    ForEach(TriggerMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .disabled(!autoShow)
                Toggle("Show the shelf next to the pointer while dragging", isOn: $settings.preferences.nearPointer)
                    .disabled(!autoShow)
                Toggle("Holding fn while dragging keeps the shelf hidden", isOn: $settings.preferences.fnSuppressesShelf)
                    .disabled(!autoShow)
            } header: {
                Text("Drag Detection")
            }

            Section {
                ExcludedAppsView(bundleIDs: $settings.preferences.excludedBundleIDs)
            } header: {
                Text("Excluded Apps")
            } footer: {
                FootnoteText("Drags that start in these apps never show the shelf.")
            }

            Section {
                Toggle("Group items dropped together into a stack", isOn: $settings.preferences.groupDropsIntoStacks)
                Toggle("Keep items after dragging them out", isOn: $settings.preferences.keepAfterDragOut)
                Toggle(
                    "Remove items whose files were deleted or moved to the Trash",
                    isOn: $settings.preferences.autoRemoveMissing
                )
            } header: {
                Text("Items")
            } footer: {
                FootnoteText(
                    "When items aren't kept, dragging one out of the shelf removes it. Lock an item "
                        + "(from its context menu) to keep it on the shelf regardless."
                )
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Storage

/// Copying policy, Recently Removed and disk usage.
struct StoragePane: View {
    @Bindable var settings: SettingsStore
    let actions: SettingsActions
    @ViewState private var storageBytes: Int64?
    @ViewState private var isMeasuring = false
    @ViewState private var recentlyRemovedCount = 0
    @ViewState private var confirmingEmpty = false

    private static let dayChoices = [1, 3, 7, 14, 30]

    private var dayOptions: [Int] {
        let current = settings.preferences.recentlyRemovedDays
        return Self.dayChoices.contains(current) ? Self.dayChoices : (Self.dayChoices + [current]).sorted()
    }

    var body: some View {
        Form {
            Section {
                Toggle(
                    "Copy files from removable and network volumes (up to 2 GB)",
                    isOn: $settings.preferences.copyFromExternalVolumes
                )
            } header: {
                Text("Files")
            } footer: {
                FootnoteText("Copies stay available after the volume is ejected. Other files are referenced, not copied.")
            }

            Section("Recently Removed") {
                Stepper(value: $settings.preferences.recentlyRemovedLimit, in: 10 ... 500, step: 10) {
                    LabeledContent("Keep up to", value: "\(settings.preferences.recentlyRemovedLimit) items")
                }
                Picker("Keep items for", selection: $settings.preferences.recentlyRemovedDays) {
                    ForEach(dayOptions, id: \.self) { days in
                        Text(days == 1 ? "1 day" : "\(days) days").tag(days)
                    }
                }
                LabeledContent("Items in Recently Removed") {
                    Text(recentlyRemovedCount, format: .number)
                        .monospacedDigit()
                }
                HStack {
                    Spacer()
                    Button("Empty Recently Removed…", role: .destructive) { confirmingEmpty = true }
                        .disabled(recentlyRemovedCount == 0)
                }
            }

            Section("Disk Usage") {
                LabeledContent("Stored by Myink") {
                    HStack(spacing: 8) {
                        if let storageBytes {
                            Text(ByteCountFormatter.string(fromByteCount: storageBytes, countStyle: .file))
                                .monospacedDigit()
                        } else {
                            Text("Calculating…").foregroundStyle(.secondary)
                        }
                        Button {
                            Task { await refreshStorage() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .disabled(isMeasuring)
                        .help("Recalculate")
                        .accessibilityLabel("Recalculate disk usage")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task {
            recentlyRemovedCount = actions.recentlyRemovedCount()
            await refreshStorage()
        }
        .confirmationDialog("Empty Recently Removed?", isPresented: $confirmingEmpty) {
            Button("Empty Recently Removed", role: .destructive) {
                actions.emptyRecentlyRemoved()
                recentlyRemovedCount = actions.recentlyRemovedCount()
                Task { await refreshStorage() }
            }
        } message: {
            Text("The removed items can no longer be brought back. This can't be undone.")
        }
    }

    private func refreshStorage() async {
        guard !isMeasuring else { return }
        isMeasuring = true
        defer { isMeasuring = false }
        recentlyRemovedCount = actions.recentlyRemovedCount()
        let measure = actions.storageUsage
        let bytes = await Task.detached(priority: .utility) { await measure() }.value
        storageBytes = bytes
    }
}

// MARK: - Automation

/// PDF service, Services shortcuts and a cheat sheet for the scripting interfaces.
struct AutomationPane: View {
    let actions: SettingsActions
    @ViewState private var pdfServiceInstalled: Bool

    init(actions: SettingsActions) {
        self.actions = actions
        _pdfServiceInstalled = State(initialValue: actions.isPDFServiceInstalled())
    }

    private var pdfServiceBinding: Binding<Bool> {
        Binding(
            get: { pdfServiceInstalled },
            set: { newValue in
                actions.setPDFServiceInstalled(newValue)
                pdfServiceInstalled = actions.isPDFServiceInstalled()
            }
        )
    }

    var body: some View {
        Form {
            Section("Print") {
                Toggle("Show 'Save PDF to Myink' in the Print dialog's PDF menu", isOn: pdfServiceBinding)
            }

            Section {
                Text(
                    "Select files in Finder or text in any app, then choose Services ▸ \"Add to Myink\" or "
                        + "\"Add Selection to Myink\". You can give these services a keyboard shortcut in "
                        + "System Settings ▸ Keyboard ▸ Keyboard Shortcuts ▸ Services."
                )
                .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("Open Keyboard Shortcuts Settings…", action: actions.openKeyboardShortcutsSettings)
                }
            } header: {
                Text("Services")
            }

            CheatSheetSection(
                title: "Open With",
                note: nil,
                code: "open -a Myink file.pdf other.png"
            )
            CheatSheetSection(
                title: "Command Line",
                note: "Install the myink command with: make install-cli",
                code: """
                myink add file.pdf other.png
                myink text "Some text"
                myink url https://example.com
                myink show | hide | toggle
                myink clear [--all]
                myink restore
                """
            )
            CheatSheetSection(
                title: "URL Scheme",
                note: "Use with open \"myink://…\" or from any app that opens links.",
                code: """
                myink://add?path=/a.pdf&path=/b.png&stack=1&reveal=0
                myink://add?url=https://example.com&title=Example
                myink://add?text=Hello
                myink://show   myink://hide   myink://toggle
                myink://clear?all=1
                myink://restore
                myink://settings
                myink://quit
                """
            )
            CheatSheetSection(
                title: "AppleScript",
                note: nil,
                code: """
                tell application "Myink"
                    add POSIX file "/path/to/file.pdf"
                    show shelf
                    clear shelf including locked true
                    restore removed items
                    get item count
                end tell
                """
            )
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            pdfServiceInstalled = actions.isPDFServiceInstalled()
        }
    }
}

/// One cheat-sheet block: monospaced, selectable sample commands.
private struct CheatSheetSection: View {
    let title: String
    let note: String?
    let code: String

    var body: some View {
        Section {
            Text(code)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        } header: {
            Text(title)
        } footer: {
            if let note {
                FootnoteText(note)
            }
        }
    }
}

/// Secondary explanatory text under a settings section.
struct FootnoteText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Titles

extension ScreenEdge {
    var title: String {
        switch self {
        case .left: "Left"
        case .right: "Right"
        case .top: "Top"
        case .bottom: "Bottom"
        }
    }

    var isVertical: Bool {
        self == .left || self == .right
    }
}

extension EdgeAlignment {
    /// Start/end read as Top/Bottom along a vertical edge and Left/Right along a horizontal one.
    func title(for edge: ScreenEdge) -> String {
        switch self {
        case .start: edge.isVertical ? "Top" : "Left"
        case .center: "Center"
        case .end: edge.isVertical ? "Bottom" : "Right"
        }
    }
}

extension ShelfSize {
    var title: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }
}

extension VisibilityMachine.IdlePolicy {
    var title: String {
        switch self {
        case .stayVisible: "Stay visible"
        case .collapse: "Collapse to a tab at the edge"
        case .hide: "Hide"
        }
    }
}

extension ScreenChoice {
    var title: String {
        switch self {
        case .underPointer: "Display under the pointer"
        case .main: "Main display"
        }
    }
}

extension TriggerMode {
    var title: String {
        switch self {
        case .onDragStart: "As soon as I start dragging"
        case .nearEdge: "When I drag near the shelf's edge"
        case .shake: "When I shake the pointer while dragging"
        case .never: "Never (use the shortcut or menu bar icon)"
        }
    }
}
