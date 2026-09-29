import AppKit

// AppleScript commands declared in Resources/Myink.sdef (`<cocoa class="MYK…Command"/>`).
// Cocoa Scripting creates and runs them on the main thread, so each command extracts Sendable
// values from its arguments and then calls `AutomationRouting.target` via `MainActor.assumeIsolated`.

/// `add <file | list of files | text> [as stack <boolean>]` → number of items added.
@objc(MYKAddCommand) final nonisolated class AddCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        let payload = ScriptAddPayload(directParameter)
        let asStack = evaluatedArguments?["asStack"] as? Bool
        guard let added = onTarget({ target in
            switch payload {
            case let .files(urls): urls.isEmpty ? 0 : target.addFiles(urls, asStack: asStack, reveal: true)
            case let .text(text): text.isEmpty ? 0 : target.addText(text, reveal: true)
            case .unsupported: 0
            }
        }) else { return fail(self, "Myink isn't ready.") }
        if added == 0, !payload.isEmpty {
            return fail(self, payload == .unsupported ? "Myink can only add files or text." : "Myink couldn't add that.")
        }
        return NSNumber(value: added)
    }
}

/// `show shelf`
@objc(MYKShowCommand) final nonisolated class ShowCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        onTarget { $0.showShelf() } == nil ? fail(self, "Myink isn't ready.") : nil
    }
}

/// `hide shelf`
@objc(MYKHideCommand) final nonisolated class HideCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        onTarget { $0.hideShelf() } == nil ? fail(self, "Myink isn't ready.") : nil
    }
}

/// `toggle shelf`
@objc(MYKToggleCommand) final nonisolated class ToggleCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        onTarget { $0.toggleShelf() } == nil ? fail(self, "Myink isn't ready.") : nil
    }
}

/// `clear shelf [including locked <boolean>]` — moves items to Recently Removed.
@objc(MYKClearCommand) final nonisolated class ClearCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        let includingLocked = evaluatedArguments?["includingLocked"] as? Bool ?? false
        return onTarget { $0.clearShelf(includingLocked: includingLocked) } == nil ? fail(self, "Myink isn't ready.") : nil
    }
}

/// `restore removed items` → number of items restored.
@objc(MYKRestoreCommand) final nonisolated class RestoreCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let restored = onTarget({ $0.restoreRemoved() }) else { return fail(self, "Myink isn't ready.") }
        return NSNumber(value: restored)
    }
}

/// The `add` command's direct parameter, converted to Sendable values before hopping to the main actor.
nonisolated enum ScriptAddPayload: Equatable {
    case files([URL])
    case text(String)
    case unsupported

    /// Accepts an NSURL, an NSString (text), or a list of NSURLs / absolute (or `~`) POSIX paths.
    init(_ value: Any?) {
        switch value {
        case let url as URL:
            self = url.isFileURL ? .files([url]) : .text(url.absoluteString)
        case let text as String:
            self = .text(text)
        case let list as [Any]:
            let urls = list.compactMap(Self.fileURL)
            self = urls.count == list.count ? .files(urls) : .unsupported
        default:
            self = .unsupported
        }
    }

    var isEmpty: Bool {
        switch self {
        case let .files(urls): urls.isEmpty
        case let .text(text): text.isEmpty
        case .unsupported: false
        }
    }

    private static func fileURL(_ element: Any) -> URL? {
        switch element {
        case let url as URL: url.isFileURL ? url : nil
        case let path as String where path.hasPrefix("/") || path.hasPrefix("~"):
            URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        default: nil
        }
    }
}

/// Runs `body` against the automation target on the main actor; nil when there is no target.
private nonisolated func onTarget<T: Sendable>(_ body: @MainActor (any AutomationTarget) -> T) -> T? {
    MainActor.assumeIsolated {
        guard let target = AutomationRouting.target else {
            Log.automation.error("script command received but no automation target is set")
            return nil
        }
        return body(target)
    }
}

/// Marks `command` as failed (AppleScript sees `errAEEventFailed` with `message`).
private nonisolated func fail(_ command: NSScriptCommand, _ message: String) -> Any? {
    Log.automation.error("script command \(command.commandDescription.commandName, privacy: .public) failed: \(message, privacy: .public)")
    command.scriptErrorNumber = Int(errAEEventFailed)
    command.scriptErrorString = message
    return nil
}
