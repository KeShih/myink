// Brings an app to the front and raises its main window via Accessibility (works when `open -a`
// won't steal focus from the active app). Usage: axfront <bundle-id>
// Build: swiftc -O -o /tmp/axfront scripts/dev/axfront.swift
import AppKit
import ApplicationServices

guard let bundleID = CommandLine.arguments.dropFirst().first,
      let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
    FileHandle.standardError.write(Data("usage: axfront <bundle-id> (app must be running)\n".utf8))
    exit(64)
}
let element = AXUIElementCreateApplication(app.processIdentifier)
AXUIElementSetAttributeValue(element, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
var windows: AnyObject?
if AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &windows) == .success,
   let first = (windows as? [AXUIElement])?.first {
    AXUIElementPerformAction(first, kAXRaiseAction as CFString)
}
app.activate()
usleep(300_000)
print(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")
