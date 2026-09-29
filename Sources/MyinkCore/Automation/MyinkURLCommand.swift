import Foundation

/// Commands for the `myink://` URL scheme. Every command is non-destructive: `clear` moves items
/// to Recently Removed, where `restore` brings them back.
///
///     myink://add?path=/abs/a.pdf&path=/abs/b.png[&stack=1][&reveal=0]
///     myink://add?url=<url>[&title=<title>]      myink://add?text=<text>
///     myink://show | hide | toggle | restore | settings | quit
///     myink://clear[?all=1]
public enum MyinkURLCommand: Equatable, Sendable {
    case addPaths([String], asStack: Bool?, reveal: Bool)
    case addURL(String, title: String?, reveal: Bool)
    case addText(String, reveal: Bool)
    case show, hide, toggle
    case clear(includingLocked: Bool)
    case restore
    case settings
    case quit

    public enum ParseError: Error, Equatable, Sendable {
        case notMyink
        case unknownCommand(String)
        case missingParameter(String)
        case relativePath(String)
    }

    public static let scheme = "myink"

    public static func parse(_ url: URL, homeDirectory: String = NSHomeDirectory()) -> Result<MyinkURLCommand, ParseError> {
        guard url.scheme?.lowercased() == scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return .failure(.notMyink) }
        let pathParts = components.path.split(separator: "/").map(String.init)
        let name = (components.host?.isEmpty == false ? components.host : pathParts.first)?.lowercased() ?? ""
        let query = components.queryItems ?? []
        func values(_ key: String) -> [String] {
            query.filter { $0.name == key }.compactMap(\.value)
        }
        func flag(_ keys: String...) -> Bool? {
            guard let value = keys.lazy.compactMap({ values($0).last }).first?.lowercased() else { return nil }
            return ["1", "true", "yes", "on"].contains(value)
        }
        let reveal = flag("reveal") ?? true

        switch name {
        case "add":
            let paths = values("path")
            if !paths.isEmpty {
                var expanded: [String] = []
                for path in paths {
                    let full = path.hasPrefix("~/") ? homeDirectory + path.dropFirst() : path
                    guard full.hasPrefix("/") else { return .failure(.relativePath(path)) }
                    expanded.append(full)
                }
                return .success(.addPaths(expanded, asStack: flag("stack", "asStack"), reveal: reveal))
            }
            if let link = values("url").first, !link.isEmpty {
                return .success(.addURL(link, title: values("title").first, reveal: reveal))
            }
            if let text = values("text").first, !text.isEmpty {
                return .success(.addText(text, reveal: reveal))
            }
            return .failure(.missingParameter("path, url or text"))
        case "show": return .success(.show)
        case "hide": return .success(.hide)
        case "toggle": return .success(.toggle)
        case "clear": return .success(.clear(includingLocked: flag("all") ?? false))
        case "restore": return .success(.restore)
        case "settings", "preferences": return .success(.settings)
        case "quit": return .success(.quit)
        default: return .failure(.unknownCommand(name))
        }
    }
}
