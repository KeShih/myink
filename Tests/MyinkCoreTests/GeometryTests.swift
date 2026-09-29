import CoreGraphics
import Foundation
@testable import MyinkCore
import Testing

@Suite("EdgeGeometry")
struct EdgeGeometryTests {
    let visible = CGRect(x: 0, y: 72, width: 2048, height: 1050)

    @Test("Shelf frames hug each edge inside the visible frame", arguments: [
        (ScreenEdge.left, CGRect(x: 8, y: 447, width: 112, height: 300)),
        (ScreenEdge.right, CGRect(x: 1928, y: 447, width: 112, height: 300)),
        (ScreenEdge.top, CGRect(x: 874, y: 1002, width: 300, height: 112)),
        (ScreenEdge.bottom, CGRect(x: 874, y: 80, width: 300, height: 112)),
    ])
    func edges(edge: ScreenEdge, expected: CGRect) {
        let frame = EdgeGeometry.shelfFrame(edge: edge, alignment: .center, visibleFrame: visible, contentLength: 300, thickness: 112, fullLength: false)
        #expect(frame == expected)
    }

    @Test("Alignment, length clamping and full length")
    func alignmentAndLength() {
        let top = EdgeGeometry.shelfFrame(edge: .left, alignment: .start, visibleFrame: visible, contentLength: 300, thickness: 112, fullLength: false)
        #expect(top.maxY == visible.maxY - EdgeGeometry.margin)
        let bottom = EdgeGeometry.shelfFrame(edge: .left, alignment: .end, visibleFrame: visible, contentLength: 300, thickness: 112, fullLength: false)
        #expect(bottom.minY == visible.minY + EdgeGeometry.margin)
        let rightEnd = EdgeGeometry.shelfFrame(edge: .bottom, alignment: .end, visibleFrame: visible, contentLength: 300, thickness: 112, fullLength: false)
        #expect(rightEnd.maxX == visible.maxX - EdgeGeometry.margin)

        let huge = EdgeGeometry.shelfFrame(edge: .left, alignment: .center, visibleFrame: visible, contentLength: 5000, thickness: 112, fullLength: false)
        #expect(abs(huge.height - (1050 - 16) * EdgeGeometry.maximumEdgeFraction) < 0.001)
        let tiny = EdgeGeometry.shelfFrame(edge: .left, alignment: .center, visibleFrame: visible, contentLength: 10, thickness: 112, fullLength: false)
        #expect(tiny.height == 112)
        let full = EdgeGeometry.shelfFrame(edge: .right, alignment: .center, visibleFrame: visible, contentLength: 10, thickness: 112, fullLength: true)
        #expect(full.height == 1034)
        #expect(full.minY == visible.minY + 8)
    }

    @Test("Slides move away from the screen, tabs sit flush at the edge")
    func slideAndTab() {
        let frame = CGRect(x: 8, y: 447, width: 112, height: 300)
        #expect(EdgeGeometry.slideFrame(from: frame, edge: .left, distance: 24).minX == -16)
        #expect(EdgeGeometry.slideFrame(from: frame, edge: .top, distance: 24).minY == 471)
        #expect(EdgeGeometry.slideFrame(from: frame, edge: .bottom, distance: 24).minY == 423)
        let leftTab = EdgeGeometry.tabFrame(edge: .left, shelfFrame: frame, visibleFrame: visible)
        #expect(leftTab == CGRect(x: 0, y: 561, width: 6, height: 72))
        let topTab = EdgeGeometry.tabFrame(edge: .top, shelfFrame: CGRect(x: 874, y: 1002, width: 300, height: 112), visibleFrame: visible)
        #expect(topTab == CGRect(x: 988, y: 1116, width: 72, height: 6))
    }

    @Test("Near-pointer frames avoid covering the pointer and stay on screen")
    func nearPointer() {
        let size = CGSize(width: 112, height: 200)
        let middle = EdgeGeometry.nearPointerFrame(pointer: CGPoint(x: 500, y: 500), size: size, visibleFrame: visible)
        #expect(middle == CGRect(x: 528, y: 400, width: 112, height: 200))
        let nearRight = EdgeGeometry.nearPointerFrame(pointer: CGPoint(x: 2000, y: 500), size: size, visibleFrame: visible)
        #expect(nearRight.maxX == 1972) // pointer.x - offset
        let nearBottom = EdgeGeometry.nearPointerFrame(pointer: CGPoint(x: 500, y: 80), size: size, visibleFrame: visible)
        #expect(nearBottom.minY == visible.minY + EdgeGeometry.margin)
    }

    @Test("Edge proximity and outer/interior edges")
    func edgeTests() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        #expect(EdgeGeometry.isNear(CGPoint(x: 10, y: 400), edge: .left, screenFrame: screen, threshold: 24))
        #expect(!EdgeGeometry.isNear(CGPoint(x: 40, y: 400), edge: .left, screenFrame: screen, threshold: 24))
        #expect(EdgeGeometry.isNear(CGPoint(x: 500, y: 760), edge: .top, screenFrame: screen, threshold: 72))
        #expect(!EdgeGeometry.isNear(CGPoint(x: 1500, y: 400), edge: .right, screenFrame: screen, threshold: 24))

        let second = CGRect(x: 1000, y: 0, width: 1200, height: 900)
        let screens = [screen, second]
        #expect(!EdgeGeometry.isOuterEdge(.right, of: screen, allScreens: screens))
        #expect(EdgeGeometry.isOuterEdge(.left, of: screen, allScreens: screens))
        #expect(!EdgeGeometry.isOuterEdge(.left, of: second, allScreens: screens))
        #expect(EdgeGeometry.isOuterEdge(.top, of: second, allScreens: screens))
        let above = CGRect(x: 0, y: 800, width: 1000, height: 600)
        #expect(!EdgeGeometry.isOuterEdge(.top, of: screen, allScreens: [screen, above]))
    }

    @Test("Screens: the one containing the point, else the nearest")
    func screenIndex() {
        let screens = [CGRect(x: 0, y: 0, width: 1000, height: 800), CGRect(x: 1000, y: 0, width: 1200, height: 900)]
        #expect(EdgeGeometry.screenIndex(containing: CGPoint(x: 1500, y: 100), screens: screens) == 1)
        #expect(EdgeGeometry.screenIndex(containing: CGPoint(x: 999.5, y: 100), screens: screens) == 0)
        #expect(EdgeGeometry.screenIndex(containing: CGPoint(x: -50, y: 100), screens: screens) == 0)
        #expect(EdgeGeometry.screenIndex(containing: CGPoint(x: 0, y: 0), screens: []) == nil)
    }
}

@Suite("ShelfLayout")
struct ShelfLayoutTests {
    let metrics = ShelfMetrics.metrics(for: .medium)
    let a = UUID(), b = UUID(), item = UUID()

    @Test("Rows stack along the shelf; stack children are shorter")
    func frames() {
        let layout = ShelfLayout(isVertical: true, metrics: metrics)
        let rows: [RowID] = [.entry(a), .child(entry: a, item: item), .entry(b)]
        let frames = layout.frames(for: rows)
        #expect(frames[0] == CGRect(x: 8, y: 8, width: 96, height: 102))
        #expect(frames[1] == CGRect(x: 8, y: 110, width: 96, height: 76))
        #expect(frames[2] == CGRect(x: 8, y: 186, width: 96, height: 102))
        #expect(layout.contentLength(for: rows) == 296) // 8 + 102 + 76 + 102 + 8

        let horizontal = ShelfLayout(isVertical: false, metrics: metrics).frames(for: [.entry(a), .entry(b)])
        #expect(horizontal[1] == CGRect(x: 110, y: 8, width: 102, height: 96))
    }

    @Test("Drop targets: between rows, or onto the middle of a row")
    func dropTargets() {
        let layout = ShelfLayout(isVertical: true, metrics: metrics)
        let frames = layout.frames(for: [.entry(a), .entry(b)])
        #expect(layout.dropTarget(at: CGPoint(x: 50, y: 12), frames: frames, allowOnto: true) == .between(0))
        #expect(layout.dropTarget(at: CGPoint(x: 50, y: 60), frames: frames, allowOnto: true) == .onto(0))
        #expect(layout.dropTarget(at: CGPoint(x: 50, y: 60), frames: frames, allowOnto: false) == .between(1))
        #expect(layout.dropTarget(at: CGPoint(x: 50, y: 105), frames: frames, allowOnto: true) == .between(1))
        #expect(layout.dropTarget(at: CGPoint(x: 50, y: 400), frames: frames, allowOnto: true) == .between(2))
        #expect(layout.rowIndex(at: CGPoint(x: 50, y: 150), frames: frames) == 1)
        #expect(layout.rowIndex(at: CGPoint(x: 50, y: 900), frames: frames) == nil)
    }

    @Test("Expanded stacks list their items after the stack row")
    func rows() {
        let stack = ShelfEntry(items: [Fixture.textItem("1"), Fixture.textItem("2")])
        let single = ShelfEntry(items: [Fixture.textItem("x")])
        #expect(ShelfRows.rows(for: [stack, single], expanded: []) == [.entry(stack.id), .entry(single.id)])
        let expanded = ShelfRows.rows(for: [stack, single], expanded: [stack.id, single.id])
        #expect(expanded == [
            .entry(stack.id), .child(entry: stack.id, item: stack.items[0].id), .child(entry: stack.id, item: stack.items[1].id), .entry(single.id),
        ])
        #expect(expanded[1].entryID == stack.id)
    }
}
