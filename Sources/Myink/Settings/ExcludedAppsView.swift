import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// `@State` resolves to SwiftUI's macro, whose plugin the Command Line Tools lack; spelling the property wrapper
/// through a typealias uses the plain `State` wrapper instead.
private typealias ViewState = State

/// The apps whose drags never show the shelf: an editable list of bundle identifiers with icons and names.
struct ExcludedAppsView: View {
    @Binding var bundleIDs: [String]
    @ViewState private var selection: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(selection: $selection) {
                ForEach(bundleIDs, id: \.self) { bundleID in
                    ExcludedAppRow(bundleID: bundleID)
                        .tag(bundleID)
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .frame(minHeight: 110, idealHeight: 130)
            .overlay {
                if bundleIDs.isEmpty {
                    Text("No excluded apps")
                        .foregroundStyle(.secondary)
                }
            }
            .onDeleteCommand(perform: removeSelected)

            HStack(spacing: 2) {
                Button(action: addFromPanel) {
                    Image(systemName: "plus").frame(width: 16, height: 16)
                }
                .help("Add an app…")
                .accessibilityLabel("Add App")
                Button(action: removeSelected) {
                    Image(systemName: "minus").frame(width: 16, height: 16)
                }
                .disabled(selection.isEmpty)
                .help("Remove the selected apps")
                .accessibilityLabel("Remove Selected Apps")
                Spacer()
                Menu("Add Running App") {
                    let apps = runningApps
                    if apps.isEmpty {
                        Text("No other apps running")
                    }
                    ForEach(apps, id: \.bundleID) { app in
                        Button {
                            append([app.bundleID])
                        } label: {
                            Label {
                                Text(app.name)
                            } icon: {
                                Image(nsImage: app.icon)
                            }
                        }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .buttonStyle(.borderless)
            .padding(.top, 6)
        }
    }

    private struct RunningApp {
        let bundleID: String
        let name: String
        let icon: NSImage
    }

    private var runningApps: [RunningApp] {
        let own = Bundle.main.bundleIdentifier
        var seen = Set(bundleIDs)
        var apps: [RunningApp] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let bundleID = app.bundleIdentifier, bundleID != own, seen.insert(bundleID).inserted else { continue }
            let icon = (app.icon?.copy() as? NSImage) ?? NSWorkspace.shared.icon(for: .application)
            icon.size = NSSize(width: 16, height: 16)
            apps.append(RunningApp(bundleID: bundleID, name: app.localizedName ?? bundleID, icon: icon))
        }
        return apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func addFromPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(filePath: "/Applications", directoryHint: .isDirectory)
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.prompt = "Exclude"
        panel.message = "Choose apps whose drags shouldn't show the shelf."
        guard panel.runModal() == .OK else { return }
        append(panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier })
    }

    private func append(_ newIDs: [String]) {
        var result = bundleIDs
        for bundleID in newIDs where !result.contains(bundleID) {
            result.append(bundleID)
        }
        if result != bundleIDs {
            bundleIDs = result
            Log.app.info("Excluded apps: \(result.count) apps")
        }
    }

    private func removeSelected() {
        guard !selection.isEmpty else { return }
        bundleIDs.removeAll { selection.contains($0) }
        selection = []
    }
}

/// An excluded app's icon and localized name, falling back to the raw bundle ID when it isn't installed.
private struct ExcludedAppRow: View {
    let bundleID: String

    var body: some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        HStack(spacing: 6) {
            Group {
                if let url {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false)))
                        .resizable()
                } else {
                    Image(systemName: "questionmark.app.dashed")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 16, height: 16)
            .accessibilityHidden(true)
            if let url {
                Text(FileManager.default.displayName(atPath: url.path(percentEncoded: false)))
                    .help(bundleID)
            } else {
                Text(bundleID)
                    .foregroundStyle(.secondary)
                    .help("Not installed")
            }
        }
    }
}
