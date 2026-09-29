import AppKit

/// Shows or hides the Dock icon. Info.plist sets `LSUIElement = YES`, so Myink launches as an
/// accessory app; `.regular` adds the Dock icon. Never activates the app (no focus stealing).
final class ActivationPolicyController {
    /// `.regular` shows the Dock icon, `.accessory` hides it.
    func apply(showInDock: Bool) {
        let policy: NSApplication.ActivationPolicy = showInDock ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        if NSApp.setActivationPolicy(policy) {
            Log.app.info("Activation policy → \(showInDock ? "regular" : "accessory", privacy: .public)")
        } else {
            Log.app.error("Failed to set activation policy (showInDock: \(showInDock))")
        }
    }
}
