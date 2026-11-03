import Foundation

/// A saved scan: one or more page images plus the filter chosen for them.
struct ScanDocument: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    let createdAt: Date
    var pageCount: Int
    var filter: ScanFilter

    init(id: UUID = UUID(), name: String, createdAt: Date = .now, pageCount: Int, filter: ScanFilter = .enhanced) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.pageCount = pageCount
        self.filter = filter
    }

    /// File-system-safe name used for exported files.
    var exportFileName: String {
        let bad = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = name.components(separatedBy: bad).joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "Scan" : cleaned
    }
}

enum ScanFilter: String, Codable, CaseIterable, Identifiable {
    case original, enhanced, grayscale, blackAndWhite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: "Original"
        case .enhanced: "Enhanced"
        case .grayscale: "Greyscale"
        case .blackAndWhite: "B&W"
        }
    }
}
