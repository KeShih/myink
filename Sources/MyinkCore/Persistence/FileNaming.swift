import Foundation

/// File-name helpers for files Myink writes into its Items directory.
public enum FileNaming {
    /// Makes `name` safe as a single path component: no slashes or colons, no leading dots,
    /// trimmed, and at most 200 characters (keeping the extension).
    public static func sanitized(_ name: String, fallback: String = "Untitled") -> String {
        var cleaned = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\0", with: "")
            .components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        while cleaned.hasPrefix(".") {
            cleaned.removeFirst()
        }
        if cleaned.isEmpty { return fallback }
        if cleaned.count > 200 {
            let ext = (cleaned as NSString).pathExtension
            let base = (cleaned as NSString).deletingPathExtension
            let keep = 200 - (ext.isEmpty ? 0 : ext.count + 1)
            cleaned = String(base.prefix(max(keep, 1))) + (ext.isEmpty ? "" : ".\(ext)")
        }
        return cleaned
    }

    /// Returns `name`, or "name 2.ext", "name 3.ext"… if it's already taken.
    public static func unique(_ name: String, existing: Set<String>) -> String {
        guard existing.contains(name) else { return name }
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        var counter = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            if !existing.contains(candidate) { return candidate }
            counter += 1
        }
    }

    /// "Image 2026-09-29 at 11.04.05.png", matching the style of macOS screenshots.
    public static func timestamped(_ prefix: String, date: Date, extension ext: String, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "\(prefix) \(formatter.string(from: date)).\(ext)"
    }
}
