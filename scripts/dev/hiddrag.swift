// Performs a real (HID-level) mouse drag for end-to-end tests. It moves the actual cursor, then puts
// it back where it was. The calling process needs Accessibility permission to post events.
//
// Usage: hiddrag <fromX> <fromY> <toX> <toY> [--via X,Y]... [--steps N] [--hold-ms N] [--option] [--command] [--fn]
// Coordinates are global CoreGraphics points (origin: top-left of the main display).
// Build:  swiftc -O -o /tmp/hiddrag scripts/dev/hiddrag.swift
import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(64)
}

var positional: [Double] = []
var waypoints: [CGPoint] = []
var steps = 24
var holdMilliseconds = 400
var flags: CGEventFlags = []
var frontBundleID: String?
var arguments = CommandLine.arguments.dropFirst().makeIterator()
while let argument = arguments.next() {
    switch argument {
    case "--via":
        guard let value = arguments.next() else { fail("--via needs X,Y") }
        let parts = value.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 2 else { fail("bad --via \(value)") }
        waypoints.append(CGPoint(x: parts[0], y: parts[1]))
    case "--steps": steps = Int(arguments.next() ?? "") ?? steps
    case "--hold-ms": holdMilliseconds = Int(arguments.next() ?? "") ?? holdMilliseconds
    case "--option": flags.insert(.maskAlternate)
    case "--command": flags.insert(.maskCommand)
    case "--fn": flags.insert(.maskSecondaryFn)
    case "--front": frontBundleID = arguments.next()
    default:
        guard let number = Double(argument) else { fail("unexpected argument \(argument)") }
        positional.append(number)
    }
}

guard positional.count == 4
else { fail("usage: hiddrag fromX fromY toX toY [--via X,Y]... [--steps N] [--hold-ms N] [--option] [--command] [--fn]") }

let source = CGEventSource(stateID: .hidSystemState)
let start = CGPoint(x: positional[0], y: positional[1])
let end = CGPoint(x: positional[2], y: positional[3])
let original = CGEvent(source: nil)?.location ?? start

func post(_ type: CGEventType, at point: CGPoint) {
    guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { return }
    event.flags = flags
    // Real presses carry a click count; some apps (Finder) won't start a drag from a count of 0.
    if type != .mouseMoved { event.setIntegerValueField(.mouseEventClickState, value: 1) }
    event.post(tap: .cghidEventTap)
}

func pause(_ milliseconds: Int) {
    usleep(useconds_t(milliseconds * 1000))
}

/// Raises the app that owns the drag start (via Accessibility) immediately before pressing, so an
/// active terminal can't take the click.
func raise(_ bundleID: String) {
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return }
    let element = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetAttributeValue(element, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
    var windows: AnyObject?
    if AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &windows) == .success,
       let first = (windows as? [AXUIElement])?.first {
        AXUIElementPerformAction(first, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(first, kAXMainAttribute as CFString, kCFBooleanTrue)
    }
}

if let frontBundleID {
    raise(frontBundleID)
    pause(150)
}

post(.mouseMoved, at: start)
pause(80)
if let frontBundleID { raise(frontBundleID) }
post(.leftMouseDown, at: start)
pause(120)

var current = start
for target in waypoints + [end] {
    for step in 1 ... steps {
        let t = Double(step) / Double(steps)
        let point = CGPoint(x: current.x + (target.x - current.x) * t, y: current.y + (target.y - current.y) * t)
        post(.leftMouseDragged, at: point)
        pause(16)
    }
    current = target
    pause(120)
}

// Linger over the destination so it receives draggingUpdated, then drop.
let lingerSteps = max(1, holdMilliseconds / 50)
for index in 0 ..< lingerSteps {
    post(.leftMouseDragged, at: CGPoint(x: end.x + (index.isMultiple(of: 2) ? 1 : 0), y: end.y))
    pause(50)
}

post(.leftMouseUp, at: end)
pause(250)
flags = []
post(.mouseMoved, at: original)
print("dragged \(start) → \(end)")
