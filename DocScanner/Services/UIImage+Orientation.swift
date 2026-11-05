import UIKit

extension UIImage {
    /// Returns the image redrawn upright at scale 1, so pixel and point sizes
    /// match and normalized coordinates mean the same thing everywhere.
    func normalizedOrientation() -> UIImage {
        if imageOrientation == .up, scale == 1, cgImage != nil { return self }
        let pixelSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: pixelSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: pixelSize))
        }
    }
}
