import AppKit
import MyinkCore
import SwiftUI

/// SwiftUI shortcut recorder control for Settings.
struct ShortcutRecorder: NSViewRepresentable {
    @Binding var combo: KeyCombo
    @Binding var isEnabled: Bool
    var onRecordingChanged: (Bool) -> Void = { _ in }

    func makeNSView(context _: Context) -> ShortcutRecorderView {
        let view = ShortcutRecorderView()
        configure(view)
        return view
    }

    func updateNSView(_ view: ShortcutRecorderView, context _: Context) {
        configure(view)
    }

    private func configure(_ view: ShortcutRecorderView) {
        view.combo = combo
        view.isShortcutEnabled = isEnabled
        let comboBinding = $combo
        let enabledBinding = $isEnabled
        view.onRecord = { newCombo in
            comboBinding.wrappedValue = newCombo
            enabledBinding.wrappedValue = true
        }
        view.onClear = { enabledBinding.wrappedValue = false }
        view.onRecordingChanged = onRecordingChanged
    }
}

/// A rounded, text-field-like control that records a global shortcut: click, then press the keys.
/// Esc cancels; Delete clears.
final class ShortcutRecorderView: NSView {
    var combo = KeyCombo.defaultShortcut {
        didSet { if combo != oldValue { refresh() } }
    }

    var isShortcutEnabled = true {
        didSet { if isShortcutEnabled != oldValue { refresh() } }
    }

    /// A valid combo was recorded.
    var onRecord: ((KeyCombo) -> Void)?
    /// The user cleared the shortcut.
    var onClear: (() -> Void)?
    var onRecordingChanged: ((Bool) -> Void)?

    private(set) var isRecording = false
    private var liveModifiers: UInt32 = 0
    private let clearButton = NSButton()
    private static let cornerRadius: CGFloat = 6

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        focusRingType = .default
        clearButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Clear shortcut")
        clearButton.isBordered = false
        clearButton.imagePosition = .imageOnly
        clearButton.contentTintColor = .tertiaryLabelColor
        clearButton.refusesFirstResponder = true
        clearButton.target = self
        clearButton.action = #selector(clearClicked)
        clearButton.toolTip = "Clear shortcut"
        addSubview(clearButton)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Keyboard shortcut")
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 150, height: 22)
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override var focusRingMaskBounds: NSRect {
        bounds
    }

    override func drawFocusRingMask() {
        Self.shape(in: bounds).fill()
    }

    override func layout() {
        super.layout()
        let side = min(bounds.height - 6, 16)
        clearButton.frame = NSRect(x: bounds.maxX - side - 4, y: bounds.midY - side / 2, width: side, height: side)
    }

    override func draw(_: NSRect) {
        let shape = Self.shape(in: bounds.insetBy(dx: 0.5, dy: 0.5))
        (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.08) : NSColor.textBackgroundColor).setFill()
        shape.fill()
        (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        shape.lineWidth = 1
        shape.stroke()

        let (text, color) = displayText
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: color
        ]
        let string = text as NSString
        let size = string.size(withAttributes: attributes)
        let trailing = clearButton.isHidden ? 0 : clearButton.frame.width + 4
        let available = bounds.insetBy(dx: 6, dy: 0)
        let originX = max(available.minX, available.midX - trailing / 2 - size.width / 2)
        string.draw(at: NSPoint(x: originX, y: bounds.midY - size.height / 2), withAttributes: attributes)
    }

    private var displayText: (String, NSColor) {
        if isRecording {
            if liveModifiers != 0 {
                return (KeyCombo(keyCode: 0, modifiers: liveModifiers).modifierSymbols, .labelColor)
            }
            return ("Type shortcut…", .placeholderTextColor)
        }
        guard isShortcutEnabled else { return ("None", .secondaryLabelColor) }
        return (KeyNameTranslator.display(combo), .labelColor)
    }

    private static func shape(in rect: NSRect) -> NSBezierPath {
        NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
    }

    private func refresh() {
        clearButton.isHidden = isRecording || !isShortcutEnabled
        setAccessibilityValue(displayText.0)
        needsDisplay = true
    }

    // MARK: Recording

    override func mouseDown(with _: NSEvent) {
        guard window?.makeFirstResponder(self) == true else { return }
        startRecording()
    }

    override func keyDown(with event: NSEvent) {
        if isRecording {
            record(event)
        } else if event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.function).isEmpty,
                  [KeyCode.space, 36, 76].contains(UInt32(event.keyCode)) {
            // Space / Return start recording, for keyboard navigation.
            startRecording()
        } else {
            super.keyDown(with: event)
        }
    }

    /// ⌘ and ⌃ combos arrive here before `keyDown(with:)`.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording, window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        record(event)
        return true
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else { return super.flagsChanged(with: event) }
        liveModifiers = KeyCombo.carbonModifiers(fromCocoaFlags: event.modifierFlags.rawValue)
        refresh()
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { stopRecording() }
        return resigned
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if let window {
            NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: window)
        }
        if let newWindow {
            NotificationCenter.default.addObserver(
                self, selector: #selector(windowDidResignKey), name: NSWindow.didResignKeyNotification, object: newWindow
            )
        } else {
            stopRecording()
        }
    }

    @objc private func windowDidResignKey(_: Notification) {
        stopRecording()
    }

    @objc private func clearClicked(_: Any?) {
        stopRecording()
        isShortcutEnabled = false
        onClear?()
    }

    private func record(_ event: NSEvent) {
        let keyCode = UInt32(event.keyCode)
        let modifiers = KeyCombo.carbonModifiers(fromCocoaFlags: event.modifierFlags.rawValue)
        if modifiers == 0, keyCode == KeyCode.escape {
            stopRecording()
            return
        }
        if modifiers == 0, keyCode == KeyCode.delete || keyCode == 117 {
            stopRecording()
            isShortcutEnabled = false
            onClear?()
            return
        }
        let candidate = KeyCombo(keyCode: keyCode, modifiers: modifiers)
        guard candidate.isValid else {
            NSSound.beep()
            return
        }
        Log.hotkey.info("Recorded shortcut \(KeyNameTranslator.display(candidate), privacy: .public)")
        stopRecording()
        combo = candidate
        isShortcutEnabled = true
        onRecord?(candidate)
    }

    private func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        liveModifiers = 0
        refresh()
        onRecordingChanged?(true)
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        liveModifiers = 0
        refresh()
        onRecordingChanged?(false)
    }
}
