import Foundation
import UIKit

/// Persists scans under Documents/Scans/<id>/ as page_N.jpg plus meta.json.
@MainActor
final class ScanStore: ObservableObject {
    @Published private(set) var documents: [ScanDocument] = []

    private let root: URL
    private let fm = FileManager.default

    init() {
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        root = docs.appendingPathComponent("Scans", isDirectory: true)
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        load()
    }

    // MARK: - Paths

    private nonisolated func folder(for id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    private nonisolated func metaURL(for id: UUID) -> URL { folder(for: id).appendingPathComponent("meta.json") }
    private nonisolated func pageURL(for id: UUID, index: Int) -> URL { folder(for: id).appendingPathComponent("page_\(index).jpg") }

    // MARK: - Loading

    private func load() {
        let folders = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        documents = folders.compactMap { url in
            guard let data = try? Data(contentsOf: url.appendingPathComponent("meta.json")) else { return nil }
            return try? decoder.decode(ScanDocument.self, from: data)
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    private func saveMeta(_ doc: ScanDocument) {
        if let data = try? JSONEncoder().encode(doc) {
            try? data.write(to: metaURL(for: doc.id), options: .atomic)
        }
    }

    // MARK: - CRUD

    @discardableResult
    func add(pages: [UIImage]) -> ScanDocument? {
        guard !pages.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        let doc = ScanDocument(name: "Scan \(formatter.string(from: .now))", pageCount: pages.count)
        do {
            try fm.createDirectory(at: folder(for: doc.id), withIntermediateDirectories: true)
            for (i, page) in pages.enumerated() {
                try page.jpegData(compressionQuality: 0.9)?.write(to: pageURL(for: doc.id, index: i))
            }
        } catch {
            return nil
        }
        saveMeta(doc)
        documents.insert(doc, at: 0)
        return doc
    }

    func update(_ doc: ScanDocument) {
        guard let i = documents.firstIndex(where: { $0.id == doc.id }) else { return }
        documents[i] = doc
        saveMeta(doc)
    }

    func delete(_ doc: ScanDocument) {
        try? fm.removeItem(at: folder(for: doc.id))
        documents.removeAll { $0.id == doc.id }
    }

    func appendPages(_ pages: [UIImage], to doc: ScanDocument) {
        var updated = doc
        for (offset, page) in pages.enumerated() {
            try? page.jpegData(compressionQuality: 0.9)?.write(to: pageURL(for: doc.id, index: doc.pageCount + offset))
        }
        updated.pageCount += pages.count
        update(updated)
    }

    // MARK: - Reading pages

    nonisolated func originalPages(for doc: ScanDocument) -> [UIImage] {
        (0..<doc.pageCount).compactMap { UIImage(contentsOfFile: pageURL(for: doc.id, index: $0).path) }
    }

    nonisolated func filteredPages(for doc: ScanDocument) -> [UIImage] {
        originalPages(for: doc).map { ImageEnhancer.apply(doc.filter, to: $0) }
    }

    nonisolated func thumbnail(for doc: ScanDocument) -> UIImage? {
        guard let first = UIImage(contentsOfFile: pageURL(for: doc.id, index: 0).path) else { return nil }
        let small = first.preparingThumbnail(of: CGSize(width: 240, height: 320)) ?? first
        return ImageEnhancer.apply(doc.filter, to: small)
    }

    // MARK: - Export

    /// Writes a PDF of the document to a temporary file and returns its URL.
    nonisolated func exportPDF(_ doc: ScanDocument) -> URL? {
        let data = PDFExporter.makePDF(from: filteredPages(for: doc))
        return writeTemp(data, name: "\(doc.exportFileName).pdf")
    }

    /// Writes each page as a JPEG to a temporary folder and returns their URLs.
    nonisolated func exportJPEGs(_ doc: ScanDocument) -> [URL] {
        filteredPages(for: doc).enumerated().compactMap { i, image in
            guard let data = image.jpegData(compressionQuality: 0.9) else { return nil }
            let suffix = doc.pageCount > 1 ? " \(i + 1)" : ""
            return writeTemp(data, name: "\(doc.exportFileName)\(suffix).jpg")
        }
    }

    private nonisolated func writeTemp(_ data: Data, name: String) -> URL? {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Export", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        do { try data.write(to: url, options: .atomic); return url } catch { return nil }
    }
}
