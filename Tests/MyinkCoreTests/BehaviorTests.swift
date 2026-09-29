import CoreGraphics
import Foundation
@testable import MyinkCore
import Testing

@Suite("VisibilityMachine")
struct VisibilityMachineTests {
    typealias Machine = VisibilityMachine

    @Test("Launch: an empty shelf hides; a shelf with items follows the idle policy")
    func launch() {
        var empty = Machine()
        #expect(empty.start() == [.hideAll])
        var withItems = Machine(itemCount: 2)
        #expect(withItems.start() == [.present(.edge)])
        #expect(withItems.base == .shown)
        var collapsing = Machine(itemCount: 2, idlePolicy: .collapse)
        #expect(collapsing.start() == [.collapseToTab])
    }

    @Test("Empty shelf: a drag reveals it, a drop keeps it")
    func dragAndDrop() {
        var machine = Machine()
        _ = machine.start()
        _ = machine.handle(.externalDragBegan)
        #expect(!machine.isVisible)
        #expect(machine.handle(.revealTriggered(.edge)) == [.present(.edge)])
        #expect(machine.isVisible)
        #expect(machine.handle(.dropCompleted) == [.present(.edge)])
        _ = machine.handle(.itemCountChanged(1))
        #expect(machine.handle(.externalDragEnded).isEmpty)
        #expect(machine.base == .shown)
        #expect(machine.isVisible)
    }

    @Test("A cancelled drag hides the shelf again after the grace period")
    func cancelledDrag() {
        var machine = Machine()
        _ = machine.start()
        _ = machine.handle(.externalDragBegan)
        _ = machine.handle(.revealTriggered(.edge))
        #expect(machine.handle(.externalDragEnded) == [.startTimer(.grace, Machine.graceInterval)])
        #expect(machine.isVisible)
        #expect(machine.handle(.timerFired(.grace)) == [.hideAll])
        #expect(!machine.isVisible)
    }

    @Test("A drop that arrives after mouse-up (during grace) still counts")
    func lateDrop() {
        var machine = Machine()
        _ = machine.start()
        _ = machine.handle(.externalDragBegan)
        _ = machine.handle(.revealTriggered(.edge))
        _ = machine.handle(.externalDragEnded)
        #expect(machine.handle(.dropCompleted) == [.cancelTimer(.grace), .present(.edge)])
        #expect(machine.handle(.timerFired(.grace)).isEmpty)
        #expect(machine.base == .shown)
    }

    @Test("Near-pointer reveals park back at the edge afterwards")
    func nearPointer() {
        var machine = Machine(itemCount: 1)
        _ = machine.start()
        _ = machine.handle(.externalDragBegan)
        let point = CGPoint(x: 300, y: 300)
        #expect(machine.handle(.revealTriggered(.nearPointer(point))) == [.present(.nearPointer(point))])
        _ = machine.handle(.externalDragEnded)
        #expect(machine.handle(.timerFired(.grace)) == [.present(.edge)])
    }

    @Test("Manual hide sticks: a drag reveals the shelf and it re-hides unless something is dropped")
    func manualHide() {
        var machine = Machine(itemCount: 1)
        _ = machine.start()
        #expect(machine.handle(.toggle).last == .hideAll)
        #expect(machine.manuallyHidden)

        _ = machine.handle(.externalDragBegan)
        #expect(machine.handle(.revealTriggered(.edge)) == [.present(.edge)])
        _ = machine.handle(.externalDragEnded)
        #expect(machine.handle(.timerFired(.grace)) == [.hideAll])

        _ = machine.handle(.externalDragBegan)
        _ = machine.handle(.revealTriggered(.edge))
        _ = machine.handle(.dropCompleted)
        _ = machine.handle(.externalDragEnded)
        #expect(!machine.manuallyHidden)
        #expect(machine.isVisible)
    }

    @Test("Toggle and show pin the shelf and make it key; hide does nothing when already hidden")
    func toggling() {
        var machine = Machine()
        _ = machine.start()
        #expect(machine.handle(.hide).isEmpty)
        let shown = machine.handle(.toggle)
        #expect(shown.contains(.present(.edge)))
        #expect(shown.last == .makeKey)
        #expect(machine.base == .pinned)
        #expect(machine.handle(.pointerExited).isEmpty)
        #expect(machine.handle(.toggle).last == .hideAll)
    }

    @Test("Collapse policy: leaving the shelf collapses it to the tab; hovering the tab reveals it")
    func collapsePolicy() {
        var machine = Machine(itemCount: 1, idlePolicy: .collapse)
        _ = machine.start()
        #expect(machine.isCollapsed)
        #expect(machine.handle(.tabActivated) == [.present(.edge), .startTimer(.autoHide, Machine.autoHideInterval)])
        #expect(machine.handle(.pointerEntered) == [.cancelTimer(.autoHide)])
        #expect(machine.handle(.pointerExited) == [.startTimer(.autoHide, Machine.autoHideInterval)])
        #expect(machine.handle(.timerFired(.autoHide)) == [.collapseToTab])
        #expect(machine.isCollapsed)
    }

    @Test("Dragging onto the tab reveals the shelf for that drag only")
    func dragOntoTab() {
        var machine = Machine(itemCount: 1, idlePolicy: .collapse)
        _ = machine.start()
        _ = machine.handle(.externalDragBegan)
        #expect(machine.handle(.tabActivated) == [.present(.edge)])
        _ = machine.handle(.externalDragEnded)
        #expect(machine.handle(.timerFired(.grace)) == [.collapseToTab])
    }

    @Test("Stay-visible never auto-hides; switching policy applies immediately")
    func policies() {
        var machine = Machine(itemCount: 2)
        _ = machine.start()
        #expect(machine.handle(.pointerExited).isEmpty)
        #expect(machine.handle(.timerFired(.autoHide)).isEmpty)
        #expect(machine.handle(.idlePolicyChanged(.hide)) == [.hideAll])
        #expect(machine.handle(.idlePolicyChanged(.collapse)) == [.collapseToTab])
        #expect(machine.handle(.idlePolicyChanged(.collapse)).isEmpty)
    }

    @Test("Dragging the last item out hides the shelf once the drag ends")
    func lastItemDraggedOut() {
        var machine = Machine(itemCount: 1)
        _ = machine.start()
        #expect(machine.handle(.internalDragBegan) == [.cancelTimer(.autoHide), .cancelTimer(.linger)])
        #expect(machine.handle(.itemCountChanged(0)).isEmpty)
        #expect(machine.handle(.internalDragEnded(pointerInside: false)) == [.hideAll])
        #expect(machine.base == .hidden)
    }

    @Test("Emptying the shelf outside a drag hides it; collapsed tabs vanish too")
    func emptying() {
        var machine = Machine(itemCount: 1)
        _ = machine.start()
        #expect(machine.handle(.itemCountChanged(0)).last == .hideAll)

        var collapsed = Machine(itemCount: 1, idlePolicy: .collapse)
        _ = collapsed.start()
        #expect(collapsed.handle(.itemCountChanged(0)).last == .hideAll)
    }

    @Test("Long press restores and shows the shelf")
    func longPress() {
        var machine = Machine()
        _ = machine.start()
        let effects = machine.handle(.longPress)
        #expect(effects.first == .restoreLatestBatch)
        #expect(effects.contains(.present(.edge)))
        #expect(effects.last == .makeKey)
    }

    @Test("Items added by automation show briefly, then respect a manual hide")
    func automationLinger() {
        var machine = Machine(itemCount: 1)
        _ = machine.start()
        _ = machine.handle(.hide)
        _ = machine.handle(.itemCountChanged(2))
        #expect(machine.handle(.itemsAddedExternally) == [.present(.edge), .startTimer(.linger, Machine.lingerInterval)])
        #expect(machine.handle(.timerFired(.linger)) == [.hideAll])

        var visible = Machine(itemCount: 1)
        _ = visible.start()
        _ = visible.handle(.itemsAddedExternally)
        #expect(visible.handle(.timerFired(.linger)).isEmpty)
        #expect(visible.isVisible)
    }

    @Test("Reveals are ignored when no drag is active")
    func revealWithoutDrag() {
        var machine = Machine()
        _ = machine.start()
        #expect(machine.handle(.revealTriggered(.edge)).isEmpty)
        #expect(machine.handle(.timerFired(.grace)).isEmpty)
    }
}

@Suite("Drag triggers")
struct DragTriggerTests {
    let screen = CGRect(x: 0, y: 0, width: 2048, height: 1152)

    private func evaluator(_ mode: TriggerMode, edge: ScreenEdge = .left, nearPointer: Bool = false) -> DragTriggerEvaluator {
        DragTriggerEvaluator(mode: mode, edge: edge, nearPointer: nearPointer, start: CGPoint(x: 1000, y: 500), startTime: 10)
    }

    @Test("On drag start: needs a little movement and time, then fires once")
    func onDragStart() {
        var trigger = evaluator(.onDragStart)
        #expect(trigger.sample(point: CGPoint(x: 1002, y: 500), time: 10.2, screenFrame: screen, isOuterEdge: true) == nil)
        #expect(trigger.sample(point: CGPoint(x: 1010, y: 500), time: 10.05, screenFrame: screen, isOuterEdge: true) == nil)
        #expect(trigger.sample(point: CGPoint(x: 1010, y: 500), time: 10.1, screenFrame: screen, isOuterEdge: true) == .edge)
        #expect(trigger.sample(point: CGPoint(x: 1100, y: 500), time: 10.2, screenFrame: screen, isOuterEdge: true) == nil)

        var nearPointer = evaluator(.onDragStart, nearPointer: true)
        #expect(nearPointer
            .sample(point: CGPoint(x: 1010, y: 500), time: 10.1, screenFrame: screen, isOuterEdge: true) == .nearPointer(CGPoint(
                x: 1010,
                y: 500
            )))
    }

    @Test("Near edge: outer edges fire at once, interior edges after a dwell, the top edge early")
    func nearEdge() {
        var outer = evaluator(.nearEdge)
        #expect(outer.sample(point: CGPoint(x: 100, y: 500), time: 11, screenFrame: screen, isOuterEdge: true) == nil)
        #expect(outer.sample(point: CGPoint(x: 10, y: 500), time: 11.1, screenFrame: screen, isOuterEdge: true) == .edge)

        var interior = evaluator(.nearEdge)
        #expect(interior.sample(point: CGPoint(x: 10, y: 500), time: 11, screenFrame: screen, isOuterEdge: false) == nil)
        #expect(interior.sample(point: CGPoint(x: 10, y: 500), time: 11.1, screenFrame: screen, isOuterEdge: false) == nil)
        #expect(interior.sample(point: CGPoint(x: 10, y: 500), time: 11.3, screenFrame: screen, isOuterEdge: false) == .edge)

        var top = evaluator(.nearEdge, edge: .top, nearPointer: true)
        #expect(top.sample(point: CGPoint(x: 900, y: 1152 - 60), time: 11, screenFrame: screen, isOuterEdge: true) == .edge)
    }

    @Test("Shake: several quick reversals trigger; slow wobbles don't")
    func shake() {
        var trigger = evaluator(.shake)
        var fired: VisibilityMachine.Placement?
        var time = 10.0
        for index in 0 ..< 12 where fired == nil {
            time += 0.05
            let x: CGFloat = index.isMultiple(of: 2) ? 1000 : 1040
            fired = trigger.sample(point: CGPoint(x: x, y: 500), time: time, screenFrame: screen, isOuterEdge: true)
        }
        #expect(fired == .edge)

        var slow = ShakeDetector()
        var detected = false
        for index in 0 ..< 12 {
            detected = detected || slow.add(CGPoint(x: index.isMultiple(of: 2) ? 1000 : 1040, y: 500), at: Double(index) * 0.5)
        }
        #expect(!detected)
        #expect(evaluator(.never).hasRevealed == false)
    }

    @Test("Acceptance: auto-show switch, never mode, fn, exclusions, Myink itself and unsupported types")
    func acceptance() {
        var preferences = Preferences()
        let files = [TypeCatalog.fileURL]
        func accepts(_ types: [String] = files, source: String? = "com.apple.finder", fn: Bool = false) -> Bool {
            DragAcceptance.accepts(
                types: types,
                sourceBundleID: source,
                fnHeld: fn,
                preferences: preferences,
                ownBundleID: "dev.keshi.myink"
            )
        }
        #expect(accepts())
        #expect(!accepts(fn: true))
        #expect(!accepts(source: "dev.keshi.myink"))
        #expect(!accepts(["com.google.chrome.tab"]))
        #expect(accepts([TypeCatalog.plainText], source: nil))
        preferences.excludedBundleIDs = ["com.apple.finder"]
        #expect(!accepts())
        preferences.excludedBundleIDs = []
        preferences.fnSuppressesShelf = false
        #expect(accepts(fn: true))
        preferences.triggerMode = .never
        #expect(!accepts())
        preferences.triggerMode = .onDragStart
        preferences.autoShowEnabled = false
        #expect(!accepts())
    }
}

@Suite("LongPressDetector")
struct LongPressDetectorTests {
    @Test("Quick release is a tap")
    func tap() {
        var detector = LongPressDetector(threshold: 1)
        #expect(detector.press(at: 0) == 1)
        #expect(detector.release(at: 0.3) == .tap)
        #expect(!detector.isPressed)
    }

    @Test("Holding past the deadline is a long press, reported once")
    func longPress() {
        var detector = LongPressDetector(threshold: 1)
        _ = detector.press(at: 5)
        #expect(detector.press(at: 5.5) == nil)
        #expect(detector.deadlineReached(at: 5.5) == nil)
        #expect(detector.deadlineReached(at: 6) == .longPress)
        #expect(detector.deadlineReached(at: 6.1) == nil)
        #expect(detector.release(at: 7) == nil)
    }

    @Test("A late release without a deadline callback still counts as a long press")
    func lateRelease() {
        var detector = LongPressDetector(threshold: 1)
        _ = detector.press(at: 0)
        #expect(detector.release(at: 1.5) == .longPress)
        #expect(detector.release(at: 2) == nil)
    }
}

@Suite("SelectionModel")
struct SelectionModelTests {
    let rows: [RowID] = (0 ..< 5).map { _ in RowID.entry(UUID()) }

    @Test("Click, ⌘-click and ⇧-click")
    func clicks() {
        var selection = SelectionModel()
        selection.click(rows[1], modifier: .none, order: rows)
        #expect(selection.selected == [rows[1]])
        selection.click(rows[3], modifier: .toggle, order: rows)
        #expect(selection.selected == [rows[1], rows[3]])
        selection.click(rows[3], modifier: .toggle, order: rows)
        #expect(selection.selected == [rows[1]])
        selection.click(rows[1], modifier: .none, order: rows)
        selection.click(rows[4], modifier: .extend, order: rows)
        #expect(selection.ordered(in: rows) == Array(rows[1 ... 4]))
        selection.click(rows[0], modifier: .extend, order: rows)
        #expect(selection.ordered(in: rows) == Array(rows[0 ... 1]))
    }

    @Test("Arrow keys move and extend; select all; pruning drops vanished rows")
    func keyboard() {
        var selection = SelectionModel()
        selection.move(by: 1, extend: false, order: rows)
        #expect(selection.selected == [rows[0]])
        selection.move(by: 1, extend: true, order: rows)
        selection.move(by: 1, extend: true, order: rows)
        #expect(selection.ordered(in: rows) == Array(rows[0 ... 2]))
        selection.move(by: -10, extend: false, order: rows)
        #expect(selection.selected == [rows[0]])
        selection.selectAll(rows)
        #expect(selection.selected.count == 5)
        selection.prune(keeping: Array(rows[2...]))
        #expect(selection.selected == Set(rows[2...]))
        selection.clear()
        #expect(selection.isEmpty)
        selection.move(by: -1, extend: false, order: rows)
        #expect(selection.selected == [rows[4]])
    }
}
