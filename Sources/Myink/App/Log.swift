import OSLog

/// Unified-logging categories. Stream them with `make logs`.
nonisolated enum Log {
    static let subsystem = "dev.keshi.myink"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let drag = Logger(subsystem: subsystem, category: "drag")
    static let shelf = Logger(subsystem: subsystem, category: "shelf")
    static let importer = Logger(subsystem: subsystem, category: "import")
    static let export = Logger(subsystem: subsystem, category: "export")
    static let store = Logger(subsystem: subsystem, category: "store")
    static let automation = Logger(subsystem: subsystem, category: "automation")
    static let hotkey = Logger(subsystem: subsystem, category: "hotkey")
}
