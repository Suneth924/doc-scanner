import Foundation

/// A saved scan: one or more page images plus the filter chosen for them.
struct ScanDocument: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    let createdAt: Date
    var pageCount: Int
    var filter: ScanFilter
    /// Document corners for each page, relative to its uncropped source photo.
    /// Optional so scans saved before manual cropping existed still load.
    var crops: [Quad]?

    init(id: UUID = UUID(), name: String, createdAt: Date = .now, pageCount: Int, filter: ScanFilter = .enhanced, crops: [Quad]? = nil) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.pageCount = pageCount
        self.filter = filter
        self.crops = crops
    }

    /// The crop for a page, or the full image when none was saved.
    func crop(at index: Int) -> Quad {
        guard let crops, crops.indices.contains(index) else { return .full }
        return crops[index]
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
