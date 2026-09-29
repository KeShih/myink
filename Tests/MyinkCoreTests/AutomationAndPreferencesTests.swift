import Foundation
@testable import MyinkCore
import Testing

@Suite("MyinkURLCommand")
struct URLCommandTests {
    private func parse(_ string: String) -> Result<MyinkURLCommand, MyinkURLCommand.ParseError> {
        MyinkURLCommand.parse(URL(string: string)!, homeDirectory: "/Users/me")
    }

    @Test("add with paths: repeated, ~-expanded, stack and reveal flags")
    func addPaths() {
        #expect(parse("myink://add?path=/tmp/a.txt&path=~/Desktop/b%20c.png&stack=1&reveal=0")
            == .success(.addPaths(["/tmp/a.txt", "/Users/me/Desktop/b c.png"], asStack: true, reveal: false)))
        #expect(parse("myink://add?path=/tmp/a.txt") == .success(.addPaths(["/tmp/a.txt"], asStack: nil, reveal: true)))
        #expect(parse("myink://add?path=relative/a.txt") == .failure(.relativePath("relative/a.txt")))
    }

    @Test("add with a URL or text")
    func addURLAndText() {
        #expect(parse("myink://add?url=https%3A%2F%2Fexample.com%2F%3Fq%3D1&title=Example") == .success(.addURL("https://example.com/?q=1", title: "Example", reveal: true)))
        #expect(parse("myink://add?text=Hello%20world%0Aline%202") == .success(.addText("Hello world\nline 2", reveal: true)))
        #expect(parse("myink:add?text=short") == .success(.addText("short", reveal: true)))
        #expect(parse("myink://add") == .failure(.missingParameter("path, url or text")))
        #expect(parse("myink://add?text=") == .failure(.missingParameter("path, url or text")))
    }

    @Test("Simple commands", arguments: [
        ("myink://show", MyinkURLCommand.show),
        ("myink://HIDE", .hide),
        ("myink://toggle", .toggle),
        ("myink://clear", .clear(includingLocked: false)),
        ("myink://clear?all=1", .clear(includingLocked: true)),
        ("myink://restore", .restore),
        ("myink://settings", .settings),
        ("myink:///quit", .quit),
    ])
    func simple(url: String, expected: MyinkURLCommand) {
        #expect(parse(url) == .success(expected))
    }

    @Test("Unknown commands and other schemes are rejected")
    func errors() {
        #expect(parse("myink://explode") == .failure(.unknownCommand("explode")))
        #expect(parse("https://example.com/show") == .failure(.notMyink))
    }
}

@Suite("Preferences")
struct PreferencesTests {
    @Test("Defaults match Yoink-like behavior")
    func defaults() {
        let preferences = Preferences()
        #expect(preferences.edge == .left)
        #expect(preferences.idlePolicy == .stayVisible)
        #expect(preferences.triggerMode == .onDragStart)
        #expect(preferences.hotKey == .defaultShortcut)
        #expect(preferences.hotKeyEnabled)
        #expect(preferences.showInMenuBar && !preferences.showInDock)
        #expect(preferences.recentlyRemovedMaxAge == 7 * 24 * 3600)
    }

    @Test("Decoding tolerates missing, unknown and invalid values")
    func tolerantDecoding() throws {
        let json = #"{"edge": "right", "triggerMode": "bogus", "recentlyRemovedDays": -3, "futureSetting": true}"#
        let preferences = try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))
        #expect(preferences.edge == .right)
        #expect(preferences.triggerMode == .onDragStart)
        #expect(preferences.recentlyRemovedDays == 0)
        #expect(preferences.size == .medium)
    }

    @Test("Round trip through UserDefaults")
    func userDefaults() throws {
        let suite = "dev.keshi.myink.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(Preferences.load(from: defaults) == Preferences())
        var preferences = Preferences()
        preferences.excludedBundleIDs = ["com.adobe.Photoshop"]
        preferences.hotKey = KeyCombo(keyCode: 46, modifiers: KeyCombo.control | KeyCombo.option)
        preferences.hotKeyEnabled = false
        preferences.save(to: defaults)
        #expect(Preferences.load(from: defaults) == preferences)
    }
}
