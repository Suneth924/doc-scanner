import UIKit

/// Builds a multi-page PDF where every page is A4 width and keeps the scan's aspect ratio.
enum PDFExporter {
    static let pageWidth: CGFloat = 595 // A4 width in points

    static func makePDF(from images: [UIImage]) -> Data {
        let first = images.first.map(pageRect(for:)) ?? CGRect(x: 0, y: 0, width: pageWidth, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: first)
        return renderer.pdfData { ctx in
            for image in images {
                let rect = pageRect(for: image)
                ctx.beginPage(withBounds: rect, pageInfo: [:])
                image.draw(in: rect)
            }
        }
    }

    private static func pageRect(for image: UIImage) -> CGRect {
        let size = image.size
        guard size.width > 0 else { return CGRect(x: 0, y: 0, width: pageWidth, height: 842) }
        return CGRect(x: 0, y: 0, width: pageWidth, height: pageWidth * size.height / size.width)
    }
}
