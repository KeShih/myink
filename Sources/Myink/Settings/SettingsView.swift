import MyinkCore
import SwiftUI

/// The root of the Settings window: one tab per pane.
struct SettingsView: View {
    @Bindable var settings: SettingsStore
    let actions: SettingsActions

    var body: some View {
        TabView {
            GeneralPane(settings: settings, actions: actions)
                .tabItem { Label("General", systemImage: "gearshape") }
            ShelfPane(settings: settings)
                .tabItem { Label("Shelf", systemImage: "sidebar.left") }
            BehaviorPane(settings: settings)
                .tabItem { Label("Behavior", systemImage: "hand.draw") }
            StoragePane(settings: settings, actions: actions)
                .tabItem { Label("Storage", systemImage: "internaldrive") }
            AutomationPane(actions: actions)
                .tabItem { Label("Automation", systemImage: "gearshape.2") }
        }
        .frame(width: 520, height: 600)
    }
}
