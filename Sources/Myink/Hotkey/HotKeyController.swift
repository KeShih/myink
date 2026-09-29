import Foundation
import MyinkCore
import Observation

/// Tap vs. long press (`LongPressDetector`, threshold 1 s) on top of `CarbonHotKey`.
@Observable
final class HotKeyController {
    /// Released before the threshold.
    @ObservationIgnored var onTap: (() -> Void)?
    /// Held for the threshold; fires once, while still held.
    @ObservationIgnored var onLongPress: (() -> Void)?

    /// While true (e.g. while recording a new shortcut in Settings) the hotkey is unregistered;
    /// setting false re-registers the last combo.
    var isSuspended = false {
        didSet {
            guard isSuspended != oldValue else { return }
            Log.hotkey.info("Hotkey \(self.isSuspended ? "suspended" : "resumed", privacy: .public)")
            apply()
        }
    }

    /// True when the OS refused the current combo (usually because another app owns it).
    private(set) var registrationFailed = false
    /// The shortcut last passed to `update(_:)`.
    private(set) var combo: KeyCombo?

    @ObservationIgnored private let hotKey = CarbonHotKey()
    @ObservationIgnored private let threshold: TimeInterval = 1.0
    @ObservationIgnored private var detector = LongPressDetector(threshold: 1.0)
    @ObservationIgnored private var deadlineTask: Task<Void, Never>?

    init() {
        hotKey.onPress = { [weak self] in self?.pressed() }
        hotKey.onRelease = { [weak self] in self?.released() }
    }

    /// Registers the shortcut, or unregisters when nil. Returns false if the OS refused it.
    @discardableResult func update(_ combo: KeyCombo?) -> Bool {
        self.combo = combo
        return apply()
    }

    @discardableResult private func apply() -> Bool {
        resetPress()
        guard let combo, !isSuspended else {
            hotKey.unregister()
            registrationFailed = false
            return true
        }
        let registered = hotKey.register(combo)
        registrationFailed = !registered
        return registered
    }

    private var now: TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    private func pressed() {
        let start = now
        guard let deadline = detector.press(at: start) else { return }
        deadlineTask?.cancel()
        deadlineTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(deadline - start))
            guard !Task.isCancelled, let self else { return }
            if detector.deadlineReached(at: now) == .longPress {
                Log.hotkey.debug("Hotkey long press")
                onLongPress?()
            }
        }
    }

    private func released() {
        deadlineTask?.cancel()
        deadlineTask = nil
        switch detector.release(at: now) {
        case .tap:
            Log.hotkey.debug("Hotkey tap")
            onTap?()
        case .longPress:
            // The deadline task didn't get to run in time (busy main thread).
            onLongPress?()
        case nil:
            break
        }
    }

    /// Forgets an in-flight press; its release may never arrive once the hotkey is unregistered.
    private func resetPress() {
        deadlineTask?.cancel()
        deadlineTask = nil
        detector = LongPressDetector(threshold: threshold)
    }
}
