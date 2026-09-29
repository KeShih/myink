import AppKit
import ServiceManagement

/// "Open at login" via `SMAppService.mainApp`.
///
/// A login item records whichever copy of the app last registered it, so only the installed copy
/// (under `/Applications` or `~/Applications`) may register; dev builds report `.notInstalledCopy`.
final class LoginItemController {
    enum State: Equatable {
        case enabled
        case disabled
        case requiresApproval
        case notInstalledCopy
        case unavailable(String)
    }

    enum LoginItemError: LocalizedError {
        case notInstalledCopy(String)

        var errorDescription: String? {
            switch self {
            case let .notInstalledCopy(path):
                "Only the copy of Myink in Applications can open at login (this one is at \(path))."
            }
        }
    }

    private let service = SMAppService.mainApp
    private let bundleURL = Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL

    var state: State {
        guard isInstalledCopy else { return .notInstalledCopy }
        switch service.status {
        case .enabled: return .enabled
        case .notRegistered, .notFound: return .disabled
        case .requiresApproval: return .requiresApproval
        @unknown default: return .unavailable("Unknown login item status (\(service.status.rawValue)).")
        }
    }

    /// True once registered, including while System Settings approval is pending.
    var isEnabled: Bool {
        let state = state
        return state == .enabled || state == .requiresApproval
    }

    /// Human-readable note for Settings (nil when enabled/disabled normally).
    var note: String? {
        switch state {
        case .enabled, .disabled:
            nil
        case .requiresApproval:
            "Myink needs approval in System Settings › General › Login Items."
        case .notInstalledCopy:
            LoginItemError.notInstalledCopy(bundleURL.path).errorDescription
        case let .unavailable(message):
            message
        }
    }

    /// Whether this copy lives in `/Applications` or `~/Applications` (including subfolders).
    var isInstalledCopy: Bool {
        let path = bundleURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath().path
        return ["/Applications/", home + "/Applications/"].contains { path.hasPrefix($0) }
    }

    func setEnabled(_ enabled: Bool) throws {
        guard isInstalledCopy else {
            // Disabling from another copy is a no-op: unregistering would drop the installed copy's item.
            if enabled { throw LoginItemError.notInstalledCopy(bundleURL.path) }
            return
        }
        if enabled {
            // Skip when registered or awaiting approval (`register()` would just fail again there).
            let status = service.status
            if status != .enabled, status != .requiresApproval {
                try service.register()
            }
            // A login launch must not also resurrect the pre-logout instance.
            NSApp.disableRelaunchOnLogin()
            Log.app.info("Login item registered (status \(self.service.status.rawValue))")
        } else {
            if service.status == .enabled || service.status == .requiresApproval {
                try service.unregister()
            }
            NSApp.enableRelaunchOnLogin()
            Log.app.info("Login item unregistered")
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
