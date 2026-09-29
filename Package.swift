// swift-tools-version: 6.2
import Foundation
import PackageDescription

// Myink is built without Xcode: `swift build` compiles the executable and scripts/bundle.sh
// assembles, signs and installs Myink.app. Resources live in Resources/ (outside Sources/) and are
// copied by the bundle script — never declare SwiftPM `resources:` (Bundle.module breaks signing).

// With only the Command Line Tools installed, SwiftPM's build engine doesn't pass the Swift Testing
// macro plugin to the compiler, so point it there explicitly when that directory exists.
let cltTestingPlugins = "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"
let testSwiftSettings: [SwiftSetting] = FileManager.default.fileExists(atPath: cltTestingPlugins)
    ? [.unsafeFlags(["-plugin-path", cltTestingPlugins])]
    : []

let package = Package(
    name: "Myink",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Myink", targets: ["Myink"])
    ],
    targets: [
        // Pure, nonisolated, fully unit-tested logic: model, persistence, import/export policy,
        // geometry, behavior state machines, URL command parsing.
        .target(name: "MyinkCore"),
        // The AppKit app. Everything is main-actor isolated unless explicitly marked otherwise.
        .executableTarget(
            name: "Myink",
            dependencies: ["MyinkCore"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "MyinkCoreTests", dependencies: ["MyinkCore"], swiftSettings: testSwiftSettings)
    ],
    swiftLanguageModes: [.v6]
)
