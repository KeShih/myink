import Carbon
import MyinkCore

/// Names keys using the current keyboard layout, so shortcuts read "⌃⌥Z" on a QWERTZ layout too.
enum KeyNameTranslator {
    /// The character the key produces in the current keyboard layout (callers uppercase it);
    /// nil if none.
    static func character(for keyCode: UInt32) -> String? {
        // Input methods (e.g. Japanese) have no Unicode layout data; fall back to an ASCII layout.
        let sources = [TISCopyCurrentKeyboardLayoutInputSource, TISCopyCurrentASCIICapableKeyboardLayoutInputSource]
        for copySource in sources {
            guard let source = copySource()?.takeRetainedValue() else { continue }
            if let character = character(for: keyCode, in: source) { return character }
        }
        return nil
    }

    /// Convenience: `combo.displayString(characterForKey: character(for:))`.
    static func display(_ combo: KeyCombo) -> String {
        combo.displayString { character(for: $0) }
    }

    private static func character(for keyCode: UInt32, in source: TISInputSource) -> String? {
        guard let rawData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let layoutData = Unmanaged<CFData>.fromOpaque(rawData).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let status = layoutData.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return OSStatus(paramErr)
            }
            return UCKeyTranslate(
                layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeyState, characters.count, &length, &characters
            )
        }
        guard status == noErr, length > 0 else { return nil }
        let string = String(utf16CodeUnits: characters, count: length)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        return string.isEmpty ? nil : string
    }
}
