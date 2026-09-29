// Prints the global frame ("x y w h", CoreGraphics coordinates) of the first accessibility element in an
// app whose title/value/description contains the given text. Used by end-to-end test scripts to find
// e.g. a file row in a Finder window. The calling process needs Accessibility permission.
//
// Usage: axfind <bundle-id> <text> [--role AXRole]
// Build:  swiftc -O -o /tmp/axfind scripts/dev/axfind.swift
import AppKit
import ApplicationServices

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: axfind <bundle-id> <text> [--role AXRole]\n".utf8))
    exit(64)
}

let bundleID = arguments[0]
let needle = arguments[1]
let wantedRole = arguments.firstIndex(of: "--role").flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }

guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
    FileHandle.standardError.write(Data("app not running: \(bundleID)\n".utf8))
    exit(66)
}

let root = AXUIElementCreateApplication(app.processIdentifier)

func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var value: AnyObject?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}

func frame(of element: AXUIElement) -> CGRect? {
    guard let positionValue = attribute(element, kAXPositionAttribute),
          let sizeValue = attribute(element, kAXSizeAttribute) else { return nil }
    var position = CGPoint.zero
    var size = CGSize.zero
    AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
    AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
    return CGRect(origin: position, size: size)
}

func search(_ element: AXUIElement, depth: Int) -> CGRect? {
    if depth > 25 { return nil }
    let role = attribute(element, kAXRoleAttribute) as? String
    let texts = [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute].compactMap { attribute(element, $0) as? String }
    if texts.contains(where: { $0.contains(needle) }), wantedRole == nil || role == wantedRole, let frame = frame(of: element),
       frame.width > 0 {
        return frame
    }
    for child in (attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? [] {
        if let found = search(child, depth: depth + 1) { return found }
    }
    return nil
}

guard let found = search(root, depth: 0) else {
    FileHandle.standardError.write(Data("not found: \(needle)\n".utf8))
    exit(1)
}

print("\(Int(found.minX)) \(Int(found.minY)) \(Int(found.width)) \(Int(found.height))")
