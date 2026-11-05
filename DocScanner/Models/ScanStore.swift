import Foundation
import UIKit

/// Persists scans under Documents/Scans/<id>/ as:
/// - source_N.jpg: the full uncropped photo, kept so edges can be re-adjusted later
/// - page_N.jpg: the cropped, perspective-corrected page (no filter applied)
/// - meta.json: name, filter and the crop corners for each page
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
    private nonisolated func sourceURL(for id: UUID, index: Int) -> URL { folder(for: id).appendingPathComponent("source_\(index).jpg") }

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
    func add(pages: [ScannedPage]) async -> ScanDocument? {
        guard !pages.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        let doc = ScanDocument(name: "Scan \(formatter.string(from: .now))", pageCount: pages.count, crops: pages.map(\.quad))
        let id = doc.id
        let ok = await Task.detached { self.writePages(pages, docID: id, startingAt: 0) }.value
        guard ok else {
            try? fm.removeItem(at: folder(for: id))
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

    func appendPages(_ pages: [ScannedPage], to doc: ScanDocument) async {
        guard !pages.isEmpty, let current = documents.first(where: { $0.id == doc.id }) else { return }
        let id = current.id
        let start = current.pageCount
        _ = await Task.detached { self.writePages(pages, docID: id, startingAt: start) }.value
        guard var updated = documents.first(where: { $0.id == id }) else { return }
        let existing = (0..<updated.pageCount).map { updated.crop(at: $0) }
        updated.crops = existing + pages.map(\.quad)
        updated.pageCount += pages.count
        update(updated)
    }

    /// Re-crops one page from its source photo with new corners.
    func updateCrop(_ quad: Quad, page index: Int, of doc: ScanDocument) async {
        guard let current = documents.first(where: { $0.id == doc.id }),
              (0..<current.pageCount).contains(index) else { return }
        let id = current.id
        let ok = await Task.detached { () -> Bool in
            guard let source = self.sourceImage(for: current, index: index) else { return false }
            return self.writePages([ScannedPage(source: source, quad: quad)], docID: id, startingAt: index)
        }.value
        guard ok, var updated = documents.first(where: { $0.id == id }) else { return }
        var crops = (0..<updated.pageCount).map { updated.crop(at: $0) }
        crops[index] = quad
        updated.crops = crops
        update(updated)
    }

    // MARK: - Writing pages

    private nonisolated func writePages(_ pages: [ScannedPage], docID: UUID, startingAt start: Int) -> Bool {
        do {
            try FileManager.default.createDirectory(at: folder(for: docID), withIntermediateDirectories: true)
            for (offset, page) in pages.enumerated() {
                try writePage(page, docID: docID, index: start + offset)
            }
            return true
        } catch {
            return false
        }
    }

    private nonisolated func writePage(_ page: ScannedPage, docID: UUID, index: Int) throws {
        let source = page.source.normalizedOrientation()
        // The source is written once and never re-encoded, so repeated edge
        // adjustments don't lose quality. Older scans have no source file;
        // their first adjustment promotes the existing page to the source.
        let sourceURL = sourceURL(for: docID, index: index)
        if !FileManager.default.fileExists(atPath: sourceURL.path) {
            try source.jpegData(compressionQuality: 0.92)?.write(to: sourceURL, options: .atomic)
        }
        let cropped = PerspectiveCorrector.correct(source, to: page.quad)
        try cropped.jpegData(compressionQuality: 0.9)?.write(to: pageURL(for: docID, index: index), options: .atomic)
    }

    // MARK: - Reading pages

    /// The uncropped photo for a page (falls back to the page itself for older scans).
    nonisolated func sourceImage(for doc: ScanDocument, index: Int) -> UIImage? {
        UIImage(contentsOfFile: sourceURL(for: doc.id, index: index).path)
            ?? UIImage(contentsOfFile: pageURL(for: doc.id, index: index).path)
    }

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
