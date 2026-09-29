import Foundation

/// Which display the shelf appears on.
public enum ScreenChoice: String, Codable, CaseIterable, Sendable {
    /// The display under the pointer (where you're dragging).
    case underPointer
    /// The display with the menu bar.
    case main
}

/// All user settings. Stored as one JSON blob in UserDefaults; decoding tolerates missing keys so
/// new settings get their defaults.
public struct Preferences: Codable, Equatable, Sendable {
    // Shelf
    public var edge: ScreenEdge = .left
    public var alignment: EdgeAlignment = .center
    public var size: ShelfSize = .medium
    public var fullLength = false
    public var idlePolicy: VisibilityMachine.IdlePolicy = .stayVisible
    public var screenChoice: ScreenChoice = .underPointer
    // Behavior
    public var autoShowEnabled = true
    public var triggerMode: TriggerMode = .onDragStart
    public var nearPointer = false
    public var fnSuppressesShelf = true
    public var excludedBundleIDs: [String] = []
    public var groupDropsIntoStacks = true
    public var keepAfterDragOut = false
    public var autoRemoveMissing = false
    // Storage
    public var copyFromExternalVolumes = false
    public var recentlyRemovedLimit = 50
    public var recentlyRemovedDays = 7
    // App
    public var showInMenuBar = true
    public var showInDock = false
    public var hotKeyEnabled = true
    public var hotKey: KeyCombo = .defaultShortcut

    public init() {}

    public static let defaultsKey = "preferences.v1"

    public var recentlyRemovedMaxAge: TimeInterval { TimeInterval(recentlyRemovedDays) * 24 * 60 * 60 }

    public static func load(from defaults: UserDefaults, key: String = defaultsKey) -> Preferences {
        guard let data = defaults.data(forKey: key), let preferences = try? JSONDecoder().decode(Preferences.self, from: data) else {
            return Preferences()
        }
        return preferences
    }

    public func save(to defaults: UserDefaults, key: String = defaultsKey) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: key)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case edge, alignment, size, fullLength, idlePolicy, screenChoice
        case autoShowEnabled, triggerMode, nearPointer, fnSuppressesShelf, excludedBundleIDs
        case groupDropsIntoStacks, keepAfterDragOut, autoRemoveMissing
        case copyFromExternalVolumes, recentlyRemovedLimit, recentlyRemovedDays
        case showInMenuBar, showInDock, hotKeyEnabled, hotKey
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Preferences()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        edge = value(.edge, defaults.edge)
        alignment = value(.alignment, defaults.alignment)
        size = value(.size, defaults.size)
        fullLength = value(.fullLength, defaults.fullLength)
        idlePolicy = value(.idlePolicy, defaults.idlePolicy)
        screenChoice = value(.screenChoice, defaults.screenChoice)
        autoShowEnabled = value(.autoShowEnabled, defaults.autoShowEnabled)
        triggerMode = value(.triggerMode, defaults.triggerMode)
        nearPointer = value(.nearPointer, defaults.nearPointer)
        fnSuppressesShelf = value(.fnSuppressesShelf, defaults.fnSuppressesShelf)
        excludedBundleIDs = value(.excludedBundleIDs, defaults.excludedBundleIDs)
        groupDropsIntoStacks = value(.groupDropsIntoStacks, defaults.groupDropsIntoStacks)
        keepAfterDragOut = value(.keepAfterDragOut, defaults.keepAfterDragOut)
        autoRemoveMissing = value(.autoRemoveMissing, defaults.autoRemoveMissing)
        copyFromExternalVolumes = value(.copyFromExternalVolumes, defaults.copyFromExternalVolumes)
        recentlyRemovedLimit = max(0, value(.recentlyRemovedLimit, defaults.recentlyRemovedLimit))
        recentlyRemovedDays = max(0, value(.recentlyRemovedDays, defaults.recentlyRemovedDays))
        showInMenuBar = value(.showInMenuBar, defaults.showInMenuBar)
        showInDock = value(.showInDock, defaults.showInDock)
        hotKeyEnabled = value(.hotKeyEnabled, defaults.hotKeyEnabled)
        hotKey = value(.hotKey, defaults.hotKey)
    }
}
