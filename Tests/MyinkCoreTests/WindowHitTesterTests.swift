import CoreGraphics
@testable import MyinkCore
import Testing

@Suite("WindowHitTester")
struct WindowHitTesterTests {
    let finderDesktop = WindowHitTester.Window(
        ownerPID: 100,
        bounds: CGRect(x: 0, y: 0, width: 1728, height: 1117),
        layer: -2_147_483_603,
        alpha: 1
    )
    let safari = WindowHitTester.Window(ownerPID: 200, bounds: CGRect(x: 100, y: 100, width: 800, height: 600), layer: 0, alpha: 1)
    let overlay = WindowHitTester.Window(ownerPID: 300, bounds: CGRect(x: 0, y: 0, width: 1728, height: 1117), layer: 1000, alpha: 1)
    let invisible = WindowHitTester.Window(ownerPID: 400, bounds: CGRect(x: 0, y: 0, width: 1728, height: 1117), layer: 0, alpha: 0)
    let myink = WindowHitTester.Window(ownerPID: 999, bounds: CGRect(x: 0, y: 0, width: 200, height: 1117), layer: 25, alpha: 1)

    @Test("Frontmost containing window wins; overlays, transparent windows and Myink are skipped")
    func hitTesting() {
        let windows = [myink, overlay, invisible, safari, finderDesktop] // front to back
        #expect(WindowHitTester.ownerPID(at: CGPoint(x: 150, y: 150), windows: windows, excludingPID: 999) == 200)
        #expect(WindowHitTester.ownerPID(at: CGPoint(x: 1500, y: 1000), windows: windows, excludingPID: 999) == 100)
        #expect(WindowHitTester.ownerPID(at: CGPoint(x: 5000, y: 5000), windows: windows, excludingPID: 999) == nil)
    }

    @Test("The Dock's transparent full-screen window doesn't hide the app underneath")
    func fullScreenOverlays() {
        let screen = CGRect(x: 0, y: 0, width: 2048, height: 1152)
        let dockOverlay = WindowHitTester.Window(ownerPID: 500, bounds: screen, layer: 20, alpha: 1)
        let menuBar = WindowHitTester.Window(ownerPID: 600, bounds: CGRect(x: 0, y: 0, width: 2048, height: 30), layer: 24, alpha: 1)
        let finderWindow = WindowHitTester.Window(
            ownerPID: 100,
            bounds: CGRect(x: 200, y: 200, width: 900, height: 600),
            layer: 0,
            alpha: 1
        )
        let desktop = WindowHitTester.Window(ownerPID: 100, bounds: screen, layer: -2_147_483_603, alpha: 1)
        let windows = [menuBar, dockOverlay, safari, finderWindow, desktop]
        #expect(WindowHitTester.ownerPID(at: CGPoint(x: 150, y: 150), windows: windows, excludingPID: 999, screenBounds: screen) == 200)
        #expect(WindowHitTester.ownerPID(at: CGPoint(x: 1000, y: 700), windows: windows, excludingPID: 999, screenBounds: screen) == 100)
        #expect(WindowHitTester.ownerPID(at: CGPoint(x: 1000, y: 10), windows: windows, excludingPID: 999, screenBounds: screen) == 600)
        // Without screen bounds the overlay can't be recognised and wins.
        #expect(WindowHitTester.ownerPID(at: CGPoint(x: 1000, y: 700), windows: windows, excludingPID: 999) == 500)
    }

    @Test("Window info dictionaries are parsed")
    func parsing() throws {
        let info: [String: Any] = [
            "kCGWindowOwnerPID": Int32(42),
            "kCGWindowBounds": ["X": 10.0, "Y": 20.0, "Width": 300.0, "Height": 200.0],
            "kCGWindowLayer": 0,
            "kCGWindowAlpha": 1.0
        ]
        let window = try #require(WindowHitTester.Window(windowInfo: info))
        #expect(window.ownerPID == 42)
        #expect(window.bounds == CGRect(x: 10, y: 20, width: 300, height: 200))
        #expect(WindowHitTester.Window(windowInfo: ["kCGWindowLayer": 0]) == nil)
    }

    @Test("AppKit points flip into CoreGraphics coordinates")
    func coordinateFlip() {
        #expect(WindowHitTester.cgPoint(fromAppKit: CGPoint(x: 10, y: 100), primaryScreenHeight: 1117) == CGPoint(x: 10, y: 1017))
    }
}
