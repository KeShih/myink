import Foundation
@testable import MyinkCore
import Testing

@Suite("KeyCombo")
struct KeyComboTests {
    @Test("F-keys are valid on their own, other keys need ⌘/⌃/⌥")
    func validation() {
        #expect(KeyCombo(keyCode: KeyCode.f5).isValid)
        #expect(!KeyCombo(keyCode: 46).isValid) // "M" alone
        #expect(!KeyCombo(keyCode: 46, modifiers: KeyCombo.shift).isValid)
        #expect(KeyCombo(keyCode: 46, modifiers: KeyCombo.control | KeyCombo.option).isValid)
        #expect(KeyCombo(keyCode: 46, modifiers: KeyCombo.command).isValid)
    }

    @Test("Display uses ⌃⌥⇧⌘ order and fixed names for special keys")
    func display() {
        let combo = KeyCombo(keyCode: 46, modifiers: KeyCombo.command | KeyCombo.shift | KeyCombo.control | KeyCombo.option)
        #expect(combo.modifierSymbols == "⌃⌥⇧⌘")
        #expect(combo.displayString(characterForKey: { _ in "m" }) == "⌃⌥⇧⌘M")
        #expect(KeyCombo.defaultShortcut.displayString() == "F5")
        #expect(KeyCombo(keyCode: KeyCode.space, modifiers: KeyCombo.option).displayString() == "⌥Space")
        #expect(KeyCombo(keyCode: 999).displayString() == "Key 999")
    }

    @Test("Cocoa modifier flags convert to Carbon modifiers")
    func carbonConversion() {
        let cocoa: UInt = (1 << 20) | (1 << 19) // ⌘⌥
        #expect(KeyCombo.carbonModifiers(fromCocoaFlags: cocoa) == KeyCombo.command | KeyCombo.option)
        #expect(KeyCombo.carbonModifiers(fromCocoaFlags: 1 << 23) == 0) // fn is ignored
    }

    @Test("Stray bits are masked off and the combo round-trips through JSON")
    func codable() throws {
        let combo = KeyCombo(keyCode: 96, modifiers: 0xFFFF_FFFF)
        #expect(combo.modifiers == KeyCombo.allModifiers)
        let data = try JSONEncoder().encode(combo)
        #expect(try JSONDecoder().decode(KeyCombo.self, from: data) == combo)
    }
}
