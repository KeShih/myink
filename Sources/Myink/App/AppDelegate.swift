import AppKit

/// M0 spike wiring: menu bar item + drag monitor + a bare drop panel at the left screen edge.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController?
    private let dragMonitor = DragMonitor()
    private var spikePanel: ShelfPanel?
    private var hideWorkItem: DispatchWorkItem?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make(settingsAction: #selector(openSettings(_:)))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.info("Myink launched from \(Bundle.main.bundlePath, privacy: .public)")
        statusItem = StatusItemController()
        dragMonitor.onEvent = { [weak self] event in self?.handle(event) }
        dragMonitor.start()
    }

    @objc func openSettings(_ sender: Any?) {
        Log.app.info("Settings requested (not implemented yet)")
    }

    private func handle(_ event: DragMonitor.Event) {
        switch event {
        case let .began(session):
            hideWorkItem?.cancel()
            showSpikePanel(near: session.startPoint)
        case .moved:
            break
        case .ended:
            let work = DispatchWorkItem { [weak self] in self?.spikePanel?.orderOut(nil) }
            hideWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
        }
    }

    private func showSpikePanel(near point: CGPoint) {
        let panel = spikePanel ?? makeSpikePanel()
        spikePanel = panel
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let size = NSSize(width: 120, height: 240)
        panel.setFrame(
            NSRect(x: visible.minX + 8, y: visible.midY - size.height / 2, width: size.width, height: size.height),
            display: true
        )
        panel.orderFrontRegardless()
        Log.shelf.debug("spike panel shown at \(NSStringFromRect(panel.frame), privacy: .public)")
    }

    private func makeSpikePanel() -> ShelfPanel {
        let panel = ShelfPanel()
        let view = SpikeDropView(frame: panel.contentLayoutRect)
        view.autoresizingMask = [.width, .height]
        view.onDrop = { [weak self] in self?.hideWorkItem?.cancel() }
        panel.contentView = view
        return panel
    }
}
