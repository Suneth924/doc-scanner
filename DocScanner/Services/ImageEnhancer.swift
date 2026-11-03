import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// Applies the scan "look" filters with Core Image.
enum ImageEnhancer {
    private static let context = CIContext()

    static func apply(_ filter: ScanFilter, to image: UIImage) -> UIImage {
        guard filter != .original, let input = CIImage(image: image) else { return image }

        let output: CIImage?
        switch filter {
        case .original:
            output = input
        case .enhanced:
            let controls = CIFilter.colorControls()
            controls.inputImage = input
            controls.contrast = 1.25
            controls.saturation = 1.1
            controls.brightness = 0.03
            let sharpen = CIFilter.sharpenLuminance()
            sharpen.inputImage = controls.outputImage
            sharpen.sharpness = 0.5
            output = sharpen.outputImage
        case .grayscale:
            let mono = CIFilter.photoEffectNoir()
            mono.inputImage = input
            let controls = CIFilter.colorControls()
            controls.inputImage = mono.outputImage
            controls.contrast = 1.2
            output = controls.outputImage
        case .blackAndWhite:
            let controls = CIFilter.colorControls()
            controls.inputImage = input
            controls.saturation = 0
            controls.contrast = 1.4
            controls.brightness = 0.08
            let threshold = CIFilter.colorThreshold()
            threshold.inputImage = controls.outputImage
            threshold.threshold = 0.55
            output = threshold.outputImage
        }

        guard let result = output,
              let cg = context.createCGImage(result, from: input.extent) else { return image }
        return UIImage(cgImage: cg, scale: image.scale, orientation: image.imageOrientation)
    }
}
