import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// Crops an image to a quad and straightens it into a flat rectangle.
enum PerspectiveCorrector {
    private static let context = CIContext()

    static func correct(_ image: UIImage, to quad: Quad) -> UIImage {
        let upright = image.normalizedOrientation()
        guard quad != .full, quad.isConvex, let cgImage = upright.cgImage else { return upright }

        let input = CIImage(cgImage: cgImage)
        let width = input.extent.width
        let height = input.extent.height
        // Core Image has a bottom-left origin and works in pixels.
        func point(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * width, y: (1 - p.y) * height) }

        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = input
        filter.topLeft = point(quad.topLeft)
        filter.topRight = point(quad.topRight)
        filter.bottomRight = point(quad.bottomRight)
        filter.bottomLeft = point(quad.bottomLeft)

        guard let output = filter.outputImage,
              let result = context.createCGImage(output, from: output.extent.integral) else { return upright }
        return UIImage(cgImage: result, scale: 1, orientation: .up)
    }
}
