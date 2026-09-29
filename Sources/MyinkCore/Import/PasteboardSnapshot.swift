import AppKit

/// Plain-value copy of pasteboard items, taken synchronously while the pasteboard is valid
/// (e.g. inside `performDragOperation`) so it can be classified and stored later.
public struct PasteboardSnapshot: Sendable, Equatable {
    public struct Item: Sendable, Equatable {
        /// Every type the item offered, in the source's order of preference.
        public var types: [String]
        /// Captured data for storable types (within the size limits).
        public var data: [String: Data]

        public init(types: [String], data: [String: Data]) {
            self.types = types
            self.data = data
        }

        public func has(_ type: String) -> Bool {
            types.contains(type)
        }

        /// Decodes a textual representation, trimming the NUL terminators some apps append.
        public func string(_ type: String) -> String? {
            guard let bytes = data[type] else { return nil }
            let decoded = type == TypeCatalog.utf16Text ? String(data: bytes, encoding: .utf16) : String(data: bytes, encoding: .utf8)
            return decoded?.trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
        }

        /// Storable representations in the source's order. Classification-only types are excluded, and
        /// so is UTF-16 text when UTF-8 text exists (AppKit regenerates it on demand).
        public var capturedRepresentations: [CapturedRepresentation] {
            let hasUTF8 = data[TypeCatalog.plainText] != nil
            return types
                .filter { TypeCatalog.isStorable($0) && !(hasUTF8 && $0.hasPrefix("public.utf16")) }
                .compactMap { type in data[type].map { CapturedRepresentation(type: type, data: $0) } }
        }
    }

    public var items: [Item]

    public init(items: [Item]) {
        self.items = items
    }

    /// Captures the storable representations of one pasteboard item, subject to the size limits.
    public static func capture(_ pasteboardItem: NSPasteboardItem) -> Item {
        let types = pasteboardItem.types.map(\.rawValue)
        var data: [String: Data] = [:]
        var total = 0
        for type in types where TypeCatalog.isStorable(type) || TypeCatalog.classificationTypes.contains(type) {
            guard let bytes = pasteboardItem.data(forType: NSPasteboard.PasteboardType(type)),
                  bytes.count <= TypeCatalog.maxRepresentationBytes,
                  total + bytes.count <= TypeCatalog.maxItemBytes else { continue }
            data[type] = bytes
            total += bytes.count
        }
        return Item(types: types, data: data)
    }

    public static func capture(_ pasteboard: NSPasteboard) -> PasteboardSnapshot {
        PasteboardSnapshot(items: (pasteboard.pasteboardItems ?? []).map(capture))
    }
}

public struct CapturedRepresentation: Sendable, Equatable {
    public var type: String
    public var data: Data

    public init(type: String, data: Data) {
        self.type = type
        self.data = data
    }
}
