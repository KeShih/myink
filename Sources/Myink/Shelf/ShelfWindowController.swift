import AppKit
import MyinkCore
import QuickLookUI

/// Owns the shelf panel and its edge tab and carries out the `VisibilityMachine`'s effects:
/// placement on the right display, slide/fade animations, timers, and drag-triggered reveals.
final class ShelfWindowController: NSObject {
    let panel = ShelfPanel()
    let viewController: ShelfViewController
    private let tab = EdgeTabPanel()
    private let settings: SettingsStore
    private let store: ShelfStore
    private var machine: VisibilityMachine
    private var timers: [VisibilityMachine.TimerKind: Task<Void, Never>] = [:]
    private var trigger: DragTriggerEvaluator?
    private var currentScreen: NSScreen?
    /// Screen chosen by a drag reveal, used by the next presentation.
    private var pendingScreen: NSScreen?
    private var placement: VisibilityMachine.Placement = .edge
    private var isPanelShown = false
    private var animationGeneration = 0
    private let slideDistance: CGFloat = 24

    /// Called whenever the shelf appears or disappears.
    var onVisibilityChanged: ((Bool) -> Void)?

    init(settings: SettingsStore, store: ShelfStore, viewController: ShelfViewController) {
        self.settings = settings
        self.store = store
        self.viewController = viewController
        machine = VisibilityMachine(itemCount: store.state.itemCount, idlePolicy: settings.preferences.idlePolicy)
        super.init()
        panel.contentViewController = viewController
        panel.delegate = self
        tab.onActivate = { [weak self] in self?.send(.tabActivated) }
        tab.onDrop = { [weak self] info in self?.dropOnTab(info) ?? false }
        wireViewController()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    var isVisible: Bool {
        machine.isVisible
    }

    func start() {
        apply(machine.start())
    }

    func send(_ event: VisibilityMachine.Event) {
        apply(machine.handle(event))
    }

    // MARK: Wiring

    private func wireViewController() {
        viewController.onPointerEntered = { [weak self] in self?.send(.pointerEntered) }
        viewController.onPointerExited = { [weak self] in self?.send(.pointerExited) }
        viewController.onDropCompleted = { [weak self] in self?.send(.dropCompleted) }
        viewController.onInternalDragBegan = { [weak self] in self?.send(.internalDragBegan) }
        viewController.onInternalDragEnded = { [weak self] inside in self?.send(.internalDragEnded(pointerInside: inside)) }
        viewController.onCancel = { [weak self] in self?.send(.hide) }
        viewController.onContentLengthChanged = { [weak self] in self?.relayoutIfVisible() }
    }

    /// The store changed: update the item count and the panel size.
    func storeChanged() {
        send(.itemCountChanged(store.state.itemCount))
    }

    /// Settings changed: reposition, resize, re-orient.
    func preferencesChanged(from old: Preferences, to new: Preferences) {
        if old.edge != new.edge || old.size != new.size {
            viewController.applyPreferences()
        }
        if old.idlePolicy != new.idlePolicy {
            send(.idlePolicyChanged(new.idlePolicy))
        }
        if old.edge != new.edge || old.alignment != new.alignment || old.size != new.size
            || old.fullLength != new.fullLength || old.screenChoice != new.screenChoice {
            if old.screenChoice != new.screenChoice { currentScreen = isPanelShown ? targetScreen() : nil }
            relayoutIfVisible()
            if machine.isCollapsed { showTab() }
        }
    }

    // MARK: Drags from other apps

    func dragBegan(_ session: DragMonitor.Session) {
        let preferences = settings.preferences
        let accepted = DragAcceptance.accepts(
            types: session.types.map(\.rawValue),
            sourceBundleID: session.source?.bundleIdentifier,
            fnHeld: session.fnHeld,
            preferences: preferences,
            ownBundleID: Bundle.main.bundleIdentifier ?? "dev.keshi.myink"
        )
        guard accepted else {
            trigger = nil
            return
        }
        trigger = DragTriggerEvaluator(
            mode: preferences.triggerMode,
            edge: preferences.edge,
            nearPointer: preferences.nearPointer,
            start: session.startPoint,
            startTime: session.startTime
        )
        send(.externalDragBegan)
    }

    func dragMoved(to point: CGPoint, at time: TimeInterval) {
        guard var evaluator = trigger, let screen = screen(containing: point) else { return }
        let frames = NSScreen.screens.map(\.frame)
        let outer = EdgeGeometry.isOuterEdge(settings.preferences.edge, of: screen.frame, allScreens: frames)
        let result = evaluator.sample(point: point, time: time, screenFrame: screen.frame, isOuterEdge: outer)
        trigger = evaluator
        if let result {
            pendingScreen = targetScreen(pointer: point)
            send(.revealTriggered(result))
        }
    }

    func dragEnded() {
        guard trigger != nil else { return }
        trigger = nil
        send(.externalDragEnded)
    }

    private func dropOnTab(_ info: any NSDraggingInfo) -> Bool {
        send(.tabActivated)
        return viewController.importDropFromTab(info)
    }

    // MARK: Effects

    private func apply(_ effects: [VisibilityMachine.Effect]) {
        for effect in effects {
            switch effect {
            case let .present(newPlacement): present(newPlacement)
            case .collapseToTab: collapseToTab()
            case .hideAll: hideAll()
            case let .startTimer(kind, interval): startTimer(kind, interval)
            case let .cancelTimer(kind): cancelTimer(kind)
            case .makeKey: makeKey()
            case .restoreLatestBatch:
                if store.restoreLatestBatch().isEmpty { NSSound.beep() }
            }
        }
    }

    private func startTimer(_ kind: VisibilityMachine.TimerKind, _ interval: TimeInterval) {
        timers[kind]?.cancel()
        timers[kind] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(interval * 1000)))
            guard !Task.isCancelled, let self else { return }
            timers[kind] = nil
            timerFired(kind, interval: interval)
        }
    }

    /// Idle timers check where the pointer really is: enter/exit events can be missed around drags.
    private func timerFired(_ kind: VisibilityMachine.TimerKind, interval: TimeInterval) {
        if kind == .autoHide || kind == .linger {
            if isPanelShown, NSMouseInRect(NSEvent.mouseLocation, panel.frame, false) {
                startTimer(kind, interval) // still over the shelf: check again later
                return
            }
            if machine.pointerInside { apply(machine.handle(.pointerExited)) }
        }
        send(.timerFired(kind))
    }

    private func cancelTimer(_ kind: VisibilityMachine.TimerKind) {
        timers[kind]?.cancel()
        timers[kind] = nil
    }

    private func makeKey() {
        panel.makeKey()
        if let list = viewController.firstResponderView { panel.makeFirstResponder(list) }
    }

    // MARK: Placement

    private func screen(containing point: CGPoint) -> NSScreen? {
        let screens = NSScreen.screens
        return EdgeGeometry.screenIndex(containing: point, screens: screens.map(\.frame)).map { screens[$0] }
    }

    private func targetScreen(pointer: CGPoint = NSEvent.mouseLocation) -> NSScreen? {
        switch settings.preferences.screenChoice {
        case .main: NSScreen.screens.first
        case .underPointer: screen(containing: pointer) ?? NSScreen.main
        }
    }

    private func frame(for placement: VisibilityMachine.Placement, on screen: NSScreen) -> NSRect {
        let preferences = settings.preferences
        let length = viewController.contentLength
        let thickness = viewController.thickness
        switch placement {
        case .edge:
            return EdgeGeometry.shelfFrame(
                edge: preferences.edge,
                alignment: preferences.alignment,
                visibleFrame: screen.visibleFrame,
                contentLength: length,
                thickness: thickness,
                fullLength: preferences.fullLength
            )
        case let .nearPointer(point):
            let compact = min(length, 340)
            let size = preferences.edge.isVertical ? NSSize(width: thickness, height: compact) : NSSize(width: compact, height: thickness)
            return EdgeGeometry.nearPointerFrame(pointer: point, size: size, visibleFrame: screen.visibleFrame)
        }
    }

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func present(_ newPlacement: VisibilityMachine.Placement) {
        hideTab()
        let screenIsGone = currentScreen.map { screen in !NSScreen.screens.contains(screen) } ?? true
        switch newPlacement {
        case let .nearPointer(point):
            currentScreen = screen(containing: point) // always beside the pointer, on its display
        case .edge:
            if let pendingScreen {
                currentScreen = pendingScreen // a drag reveal: the display the drag is on
            } else if !isPanelShown || screenIsGone {
                currentScreen = targetScreen()
            }
        }
        pendingScreen = nil
        guard let screen = currentScreen ?? targetScreen() else { return }
        currentScreen = screen
        placement = newPlacement
        let target = frame(for: newPlacement, on: screen)
        animationGeneration += 1

        if isPanelShown, panel.isVisible {
            guard panel.frame != target else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = reduceMotion ? 0 : 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(target, display: true)
                panel.animator().alphaValue = 1
            }
            return
        }

        isPanelShown = true
        let start: NSRect = if reduceMotion { target } else if case .edge = newPlacement {
            EdgeGeometry.slideFrame(from: target, edge: settings.preferences.edge, distance: slideDistance)
        } else {
            target
        }
        panel.setFrame(start, display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        store.refreshAvailability()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 1
        }
        onVisibilityChanged?(true)
        Log.shelf.debug("shelf shown at \(NSStringFromRect(target), privacy: .public)")
    }

    private func hideAll() {
        hideTab()
        hidePanel()
    }

    private func collapseToTab() {
        hidePanel()
        showTab()
    }

    private func hidePanel() {
        viewController.closeQuickLook()
        guard isPanelShown else { return }
        isPanelShown = false
        animationGeneration += 1
        let generation = animationGeneration
        let end = reduceMotion ? panel.frame : EdgeGeometry.slideFrame(
            from: panel.frame,
            edge: settings.preferences.edge,
            distance: slideDistance
        )
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(end, display: true)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, generation == self.animationGeneration else { return }
                self.panel.orderOut(nil)
            }
        }
        onVisibilityChanged?(false)
        Log.shelf.debug("shelf hidden")
    }

    private func showTab() {
        guard let screen = currentScreen ?? targetScreen() else { return }
        let shelfFrame = frame(for: .edge, on: screen)
        tab.setFrame(
            EdgeGeometry.tabFrame(edge: settings.preferences.edge, shelfFrame: shelfFrame, visibleFrame: screen.visibleFrame),
            display: true
        )
        tab.isVertical = settings.preferences.edge.isVertical
        tab.orderFrontRegardless()
    }

    private func hideTab() {
        tab.orderOut(nil)
    }

    private func relayoutIfVisible() {
        guard isPanelShown, let screen = currentScreen else { return }
        let target = frame(for: placement, on: screen)
        guard target != panel.frame else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0 : 0.18
            panel.animator().setFrame(target, display: true)
        }
    }

    @objc private func screensChanged() {
        if let screen = currentScreen, !NSScreen.screens.contains(screen) {
            currentScreen = nil
        }
        if isPanelShown {
            currentScreen = currentScreen ?? targetScreen()
            placement = .edge
            relayoutIfVisible()
        } else if machine.isCollapsed {
            showTab()
        }
    }
}

extension ShelfWindowController: NSWindowDelegate {
    func windowDidResignKey(_ notification: Notification) {
        // Clicking into Quick Look makes it key; only close it when focus went somewhere else.
        Task { @MainActor [weak self] in
            if NSApp.keyWindow is QLPreviewPanel || NSApp.keyWindow === self?.panel { return }
            self?.viewController.closeQuickLook()
        }
    }
}

/// The thin pill shown at the screen edge while the shelf is collapsed. Hovering it or dragging onto
/// it reveals the shelf; dropping directly onto it adds the items.
final class EdgeTabPanel: ShelfPanel {
    var onActivate: (() -> Void)?
    var onDrop: ((any NSDraggingInfo) -> Bool)?
    var isVertical = true

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 6, height: 72))
        hasShadow = false
        let view = EdgeTabView()
        view.panel = self
        contentView = view
    }
}

private final class EdgeTabView: NSView {
    weak var panel: EdgeTabPanel?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes(TypeCatalog.acceptedDragTypes.map { NSPasteboard.PasteboardType($0) })
        setAccessibilityRole(.button)
        setAccessibilityLabel("Show Myink shelf")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
        NSColor.controlAccentColor.withAlphaComponent(0.85).setFill()
        path.fill()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        panel?.onActivate?()
    }

    override func mouseDown(with event: NSEvent) {
        panel?.onActivate?()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        panel?.onActivate?()
        return DropPolicy.operation(sourceMask: sender.draggingSourceOperationMask, isInternal: false)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        DropPolicy.operation(sourceMask: sender.draggingSourceOperationMask, isInternal: false)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        panel?.onDrop?(sender) ?? false
    }
}
