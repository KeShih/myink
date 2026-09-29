import Carbon
import MyinkCore

/// One Carbon global hotkey with press and release callbacks.
final class CarbonHotKey {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    /// 'MYNK', identifying Myink's hotkeys among all hotkey events on the dispatcher target.
    nonisolated static let signature: FourCharCode = 0x4D59_4E4B
    private static var nextID: UInt32 = 1

    /// Distinguishes this instance's events from those of other `CarbonHotKey`s.
    let hotKeyID: UInt32
    private nonisolated(unsafe) var handlerRef: EventHandlerRef?
    private nonisolated(unsafe) var hotKeyRef: EventHotKeyRef?

    init() {
        hotKeyID = Self.nextID
        Self.nextID += 1
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        let status = InstallEventHandler(
            GetEventDispatcherTarget(), carbonHotKeyHandler, specs.count, &specs,
            Unmanaged.passUnretained(self).toOpaque(), &handlerRef
        )
        if status != noErr {
            Log.hotkey.error("InstallEventHandler failed: \(status)")
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }

    /// Registers the combo (replacing any previous one). Returns false if registration failed
    /// (e.g. `eventHotKeyExistsErr`: taken by another app).
    @discardableResult func register(_ combo: KeyCombo) -> Bool {
        unregister()
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: hotKeyID)
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, id, GetEventDispatcherTarget(), 0, &ref)
        let name = combo.displayString()
        guard status == noErr, let ref else {
            Log.hotkey.error("RegisterEventHotKey \(name, privacy: .public) failed: \(status)")
            return false
        }
        hotKeyRef = ref
        Log.hotkey.info("Registered hotkey \(name, privacy: .public)")
        return true
    }

    func unregister() {
        guard let hotKeyRef else { return }
        UnregisterEventHotKey(hotKeyRef)
        self.hotKeyRef = nil
    }

    fileprivate func didPress() {
        onPress?()
    }

    fileprivate func didRelease() {
        onRelease?()
    }
}

/// `EventHandlerUPP` for hotkey events; `userData` is the unretained `CarbonHotKey`. Carbon
/// dispatches on the main thread.
private nonisolated func carbonHotKeyHandler(
    _: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var eventID = EventHotKeyID()
    let status = GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
        nil, MemoryLayout<EventHotKeyID>.size, nil, &eventID
    )
    guard status == noErr, eventID.signature == CarbonHotKey.signature else { return OSStatus(eventNotHandledErr) }
    let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
    let id = eventID.id
    let address = UInt(bitPattern: userData)
    let handled = MainActor.assumeIsolated {
        guard let pointer = UnsafeMutableRawPointer(bitPattern: address) else { return false }
        let hotKey = Unmanaged<CarbonHotKey>.fromOpaque(pointer).takeUnretainedValue()
        guard hotKey.hotKeyID == id else { return false }
        pressed ? hotKey.didPress() : hotKey.didRelease()
        return true
    }
    return handled ? noErr : OSStatus(eventNotHandledErr)
}
