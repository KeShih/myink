import AppKit

/// Detects drags that start anywhere on the system.
///
/// There is no public API for this, so Myink uses the standard technique: global mouse monitors
/// (which need no permission) plus the drag pasteboard's `changeCount`, which bumps when a source app
/// writes a new drag. While the button is down a 60 Hz poll provides pointer samples and detects the
/// end of the drag even if the source's drag loop starves the global monitors.
///
/// Only the pasteboard's `changeCount` and `types` are read during a drag — never data or URLs,
/// which can interfere with the file-access grant that happens at drop time.
final class DragMonitor {
    struct Session: Equatable {
        var types: [NSPasteboard.PasteboardType]
        var startPoint: CGPoint
        var startTime: TimeInterval
        var source: SourceAppResolver.Source?
        var fnHeld: Bool
    }

    enum Event {
        case began(Session)
        case moved(CGPoint, TimeInterval)
        case ended
    }

    var onEvent: ((Event) -> Void)?
    /// Suspends detection (e.g. while Myink runs its own drag-out session).
    var isPaused = false

    private let dragPasteboard = NSPasteboard(name: .drag)
    private let resolver = SourceAppResolver()
    private var monitors: [Any] = []
    private var pollTimer: Timer?
    private var buttonDown = false
    private var baselineChangeCount = 0
    private var mouseDownPoint: CGPoint = .zero
    private var mouseDownTime: TimeInterval = 0
    private(set) var session: Session?

    /// How long to wait for a source to fill the pasteboard with types after `changeCount` moved.
    private let emptyTypesGrace: TimeInterval = 0.25

    func start() {
        guard monitors.isEmpty else { return }
        addMonitor(.leftMouseDown) { $0.mouseDown() }
        addMonitor(.leftMouseDragged) { $0.poll() }
        addMonitor(.leftMouseUp) { $0.finish() }
        Log.drag.info("drag monitor started (\(self.monitors.count) global monitors)")
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        stopPolling()
        buttonDown = false
        session = nil
    }

    private func addMonitor(_ mask: NSEvent.EventTypeMask, _ handler: @escaping (DragMonitor) -> Void) {
        let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                handler(self)
            }
        }
        if let monitor { monitors.append(monitor) } else { Log.drag.error("could not install global monitor for \(mask.rawValue)") }
    }

    private func mouseDown() {
        guard !isPaused else { return }
        buttonDown = true
        session = nil
        baselineChangeCount = dragPasteboard.changeCount
        mouseDownPoint = NSEvent.mouseLocation
        mouseDownTime = ProcessInfo.processInfo.systemUptime
        startPolling()
    }

    private func poll() {
        guard buttonDown else { return }
        if NSEvent.pressedMouseButtons & 1 == 0 {
            finish()
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        if session == nil {
            detectDragStart(now: now)
        }
        if session != nil {
            onEvent?(.moved(NSEvent.mouseLocation, now))
        }
    }

    private func detectDragStart(now: TimeInterval) {
        guard !isPaused, dragPasteboard.changeCount != baselineChangeCount else { return }
        let types = dragPasteboard.types ?? []
        if types.isEmpty, now - mouseDownTime < emptyTypesGrace { return }
        let newSession = Session(
            types: types,
            startPoint: mouseDownPoint,
            startTime: now,
            source: resolver.resolve(atAppKitPoint: mouseDownPoint),
            fnHeld: NSEvent.modifierFlags.contains(.function)
        )
        session = newSession
        Log.drag.debug("""
        drag began from \(newSession.source?.bundleIdentifier ?? "?", privacy: .public) \
        after \(Int((now - self.mouseDownTime) * 1000))ms, types: \(types.map(\.rawValue).joined(separator: ", "), privacy: .public)
        """)
        onEvent?(.began(newSession))
    }

    private func finish() {
        stopPolling()
        buttonDown = false
        guard session != nil else { return }
        session = nil
        Log.drag.debug("drag ended")
        onEvent?(.ended)
    }

    private func startPolling() {
        stopPolling()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}
