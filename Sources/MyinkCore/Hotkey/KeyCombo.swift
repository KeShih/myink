import Foundation

/// A global keyboard shortcut expressed the way Carbon's `RegisterEventHotKey` wants it:
/// a virtual key code plus a Carbon modifier mask.
public struct KeyCombo: Codable, Hashable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32 = 0) {
        self.keyCode = keyCode
        self.modifiers = modifiers & Self.allModifiers
    }

    // Carbon modifier bits (HIToolbox/Events.h).
    public static let command: UInt32 = 1 << 8
    public static let shift: UInt32 = 1 << 9
    public static let option: UInt32 = 1 << 11
    public static let control: UInt32 = 1 << 12
    public static let allModifiers: UInt32 = command | shift | option | control

    /// Yoink's default: F5 on its own.
    public static let defaultShortcut = KeyCombo(keyCode: KeyCode.f5)

    public var isFunctionKey: Bool {
        KeyCode.functionKeyNames[keyCode] != nil
    }

    /// Function keys may be used alone; any other key needs ⌘, ⌃ or ⌥ so the shortcut
    /// can't swallow ordinary typing.
    public var isValid: Bool {
        if isFunctionKey { return true }
        return modifiers & (Self.command | Self.control | Self.option) != 0
    }

    /// Modifier glyphs in the conventional macOS order: ⌃⌥⇧⌘.
    public var modifierSymbols: String {
        var symbols = ""
        if modifiers & Self.control != 0 { symbols += "⌃" }
        if modifiers & Self.option != 0 { symbols += "⌥" }
        if modifiers & Self.shift != 0 { symbols += "⇧" }
        if modifiers & Self.command != 0 { symbols += "⌘" }
        return symbols
    }

    /// Human-readable form, e.g. "⌃⌥M" or "F5". `characterForKey` translates ordinary keys using
    /// the current keyboard layout (supplied by the app); special keys use fixed names.
    public func displayString(characterForKey: (UInt32) -> String? = { _ in nil }) -> String {
        let key = KeyCode.specialKeyName(for: keyCode)
            ?? characterForKey(keyCode)?.uppercased()
            ?? "Key \(keyCode)"
        return modifierSymbols + key
    }

    /// Converts `NSEvent.ModifierFlags.rawValue` into a Carbon modifier mask.
    public static func carbonModifiers(fromCocoaFlags rawFlags: UInt) -> UInt32 {
        var result: UInt32 = 0
        if rawFlags & CocoaFlag.command != 0 { result |= command }
        if rawFlags & CocoaFlag.shift != 0 { result |= shift }
        if rawFlags & CocoaFlag.option != 0 { result |= option }
        if rawFlags & CocoaFlag.control != 0 { result |= control }
        return result
    }

    /// `NSEvent.ModifierFlags` raw values, kept here so Core stays free of AppKit.
    enum CocoaFlag {
        static let shift: UInt = 1 << 17
        static let control: UInt = 1 << 18
        static let option: UInt = 1 << 19
        static let command: UInt = 1 << 20
    }
}

/// Virtual key codes (HIToolbox/Events.h `kVK_*`).
public enum KeyCode {
    public static let f5: UInt32 = 96
    public static let space: UInt32 = 49
    public static let escape: UInt32 = 53
    public static let delete: UInt32 = 51

    static let functionKeyNames: [UInt32: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
        106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20"
    ]

    static let otherKeyNames: [UInt32: String] = [
        49: "Space", 36: "↩", 76: "⌅", 48: "⇥", 51: "⌫", 117: "⌦", 53: "⎋",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟", 123: "←", 124: "→", 125: "↓", 126: "↑",
        114: "Help"
    ]

    public static func specialKeyName(for keyCode: UInt32) -> String? {
        functionKeyNames[keyCode] ?? otherKeyNames[keyCode]
    }
}
