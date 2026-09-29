// Lists on-screen windows (owner, layer, bounds in global top-left coordinates) for E2E test scripting.
// Usage: swift scripts/dev/windows.swift [owner-substring]
import CoreGraphics
import Foundation

let filter = CommandLine.arguments.dropFirst().first?.lowercased()
let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
for window in info {
    let owner = window[kCGWindowOwnerName as String] as? String ?? "?"
    if let filter, !owner.lowercased().contains(filter) { continue }
    let layer = window[kCGWindowLayer as String] as? Int ?? 0
    let bounds = window[kCGWindowBounds as String] as? [String: Double] ?? [:]
    let name = window[kCGWindowName as String] as? String ?? ""
    print(
        "\(owner)\tlayer=\(layer)\tx=\(Int(bounds["X"] ?? 0)) y=\(Int(bounds["Y"] ?? 0)) w=\(Int(bounds["Width"] ?? 0)) h=\(Int(bounds["Height"] ?? 0))\t\(name)"
    )
}
