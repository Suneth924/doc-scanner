import CoreVideo
import UIKit
import Vision

/// Finds the document outline in an image.
///
/// Two Vision requests run together:
/// - `VNDetectDocumentSegmentationRequest`, a machine-learning model trained on
///   documents. It copes with busy backgrounds, low contrast and partly
///   covered pages, but its mask is low resolution so the corners can be a few
///   pixels off.
/// - `VNDetectRectanglesRequest`, a classic edge-based detector. It is precise
///   when it locks on, but it also finds tables, screens and picture frames.
///
/// We use the segmentation outline to decide *which* shape is the page and,
/// when a rectangle agrees with it, snap to that rectangle's sharper corners.
enum EdgeDetector {
    /// Detects the document in an upright image.
    static func detect(in image: UIImage) -> Quad? {
        let upright = image.normalizedOrientation()
        guard let cgImage = upright.cgImage else { return nil }
        return detect(with: VNImageRequestHandler(cgImage: cgImage, orientation: .up))
    }

    /// Detects the document in a camera frame. `orientation` is how the buffer
    /// must be rotated to appear upright (`.right` for the back camera held in portrait).
    static func detect(pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> Quad? {
        detect(with: VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation))
    }

    private static func detect(with handler: VNImageRequestHandler) -> Quad? {
        let segmentation = VNDetectDocumentSegmentationRequest()

        let rectangles = VNDetectRectanglesRequest()
        rectangles.maximumObservations = 8
        rectangles.minimumConfidence = 0.6
        rectangles.minimumSize = 0.15
        rectangles.minimumAspectRatio = 0.25
        rectangles.maximumAspectRatio = 1.0
        rectangles.quadratureTolerance = 25 // degrees; pages seen at an angle are not perfect rectangles

        do {
            try handler.perform([segmentation, rectangles])
        } catch {
            return nil
        }

        let document = segmentation.results?
            .filter { $0.confidence >= 0.5 }
            .max { $0.confidence < $1.confidence }
            .map(quad(from:))
        let candidates = (rectangles.results ?? []).map(quad(from:))
        return choose(document: document, rectangles: candidates)
    }

    static func choose(document: Quad?, rectangles: [Quad]) -> Quad? {
        let rectangles = rectangles.filter(\.isConvex)

        if let document, document.isConvex, document.area > 0.04 {
            // Snap to an edge-detected rectangle that matches the ML outline.
            let tolerance: CGFloat = 0.05
            let snapped = rectangles
                .filter { $0.maxCornerDistance(to: document) < tolerance }
                .min { $0.maxCornerDistance(to: document) < $1.maxCornerDistance(to: document) }
            return snapped ?? document
        }

        // No confident document outline: fall back to the biggest rectangle.
        return rectangles.max { $0.area < $1.area }
    }

    /// Vision uses a bottom-left origin; Quad uses top-left.
    private static func quad(from observation: VNRectangleObservation) -> Quad {
        func flip(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: 1 - p.y) }
        return Quad(
            topLeft: flip(observation.topLeft),
            topRight: flip(observation.topRight),
            bottomRight: flip(observation.bottomRight),
            bottomLeft: flip(observation.bottomLeft)
        )
    }
}
