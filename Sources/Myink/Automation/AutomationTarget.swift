import AppKit

/// What automation (Services, the `myink://` URL scheme, AppleScript) needs from the app.
/// Implemented by the app's composition root. Every `add…` returns the number of items added.
protocol AutomationTarget: AnyObject {
    @discardableResult func addFiles(_ urls: [URL], asStack: Bool?, reveal: Bool) -> Int
    @discardableResult func addText(_ text: String, reveal: Bool) -> Int
    @discardableResult func addLink(_ url: String, title: String?, reveal: Bool) -> Int
    /// Imports a (non-drag) pasteboard, e.g. a Services pasteboard. Returns items added.
    @discardableResult func addPasteboard(_ pasteboard: NSPasteboard, reveal: Bool) -> Int
    func showShelf()
    func hideShelf()
    func toggleShelf()
    /// Moves items to Recently Removed. Returns items removed.
    @discardableResult func clearShelf(includingLocked: Bool) -> Int
    /// Puts the most recently removed items back. Returns items restored.
    @discardableResult func restoreRemoved() -> Int
    func openSettings()
    /// Items on the shelf (a stack counts each of its items).
    var itemCount: Int { get }
}

/// Where scripting commands find the app: Cocoa Scripting instantiates `NSScriptCommand`s itself,
/// so they can't be handed a target. Set by the composition root at launch.
enum AutomationRouting {
    weak static var target: (any AutomationTarget)?
}
