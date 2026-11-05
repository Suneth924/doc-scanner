import AVFoundation
import SwiftUI

/// Live camera preview with the detected document outline drawn on top.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let quad: Quad?

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        view.quad = quad
    }
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

    private let outline = CAShapeLayer()

    var quad: Quad? {
        didSet { if quad != oldValue { updateOutline() } }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        previewLayer.videoGravity = .resizeAspectFill
        outline.strokeColor = UIColor.systemBlue.cgColor
        outline.fillColor = UIColor.systemBlue.withAlphaComponent(0.2).cgColor
        outline.lineWidth = 3
        outline.lineJoin = .round
        layer.addSublayer(outline)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        outline.frame = bounds
        updateOutline()
    }

    private func updateOutline() {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.12)
        defer { CATransaction.commit() }

        guard let quad else {
            outline.path = nil
            return
        }
        // Quad is in portrait image coordinates; capture-device coordinates are
        // the landscape sensor's, so rotate back before letting the layer map
        // them (it accounts for aspect-fill cropping).
        let points = quad.corners.map { p in
            previewLayer.layerPointConverted(fromCaptureDevicePoint: CGPoint(x: p.y, y: 1 - p.x))
        }
        let path = UIBezierPath()
        path.move(to: points[0])
        points.dropFirst().forEach { path.addLine(to: $0) }
        path.close()
        outline.path = path.cgPath
    }
}
