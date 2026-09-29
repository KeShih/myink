import AppKit

// AppKit lifecycle (no SwiftUI App): Myink is an accessory app whose windows are an NSPanel shelf,
// a status item and a Settings window.
let appDelegate = AppDelegate()
let application = NSApplication.shared
application.delegate = appDelegate
application.run()
