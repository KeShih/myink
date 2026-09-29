import AppKit
import QuickLookUI

/// Feeds the shared Quick Look panel from the shelf. The shelf panel stays key (so arrow keys keep
/// working in the list); the Quick Look panel is ordered front above it without taking focus.
final class QuickLookCoordinator: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    private(set) var urls: [URL] = []
    /// Screen frame of the item at an index (for the zoom animation).
    var sourceFrame: ((Int) -> NSRect)?
    /// Keys pressed while Quick Look is frontmost are forwarded here (arrows, space, escape).
    var onKeyDown: ((NSEvent) -> Bool)?
    var level: NSWindow.Level = .statusBar

    var isVisible: Bool {
        QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible
    }

    func update(urls newURLs: [URL]) {
        urls = newURLs
        guard isVisible else { return }
        QLPreviewPanel.shared().reloadData()
    }

    /// Call from the responder that accepted control, after `beginPreviewPanelControl`.
    func begin(_ panel: QLPreviewPanel) {
        panel.dataSource = self
        panel.delegate = self
        panel.level = NSWindow.Level(rawValue: level.rawValue + 1)
        panel.hidesOnDeactivate = false
        panel.reloadData()
    }

    func end(_ panel: QLPreviewPanel) {
        panel.dataSource = nil
        panel.delegate = nil
    }

    func toggle(urls newURLs: [URL]) {
        let panel = QLPreviewPanel.shared()!
        if isVisible {
            panel.orderOut(nil)
            return
        }
        guard !newURLs.isEmpty else {
            NSSound.beep()
            return
        }
        urls = newURLs
        panel.updateController()
        panel.orderFront(nil)
        panel.reloadData()
    }

    func close() {
        guard isVisible else { return }
        QLPreviewPanel.shared().orderOut(nil)
    }

    // MARK: QLPreviewPanelDataSource

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        urls.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        urls.indices.contains(index) ? urls[index] as NSURL : nil
    }

    // MARK: QLPreviewPanelDelegate

    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard let event, event.type == .keyDown else { return false }
        return onKeyDown?(event) ?? false
    }

    func previewPanel(_ panel: QLPreviewPanel!, sourceFrameOnScreenFor item: (any QLPreviewItem)!) -> NSRect {
        guard let url = item.previewItemURL, let index = urls.firstIndex(of: url) else { return .zero }
        return sourceFrame?(index) ?? .zero
    }
}
