import AVFoundation
import UIKit

/// Runs the back camera, detects the document outline live on video frames
/// and captures full-resolution photos.
/// State is confined to sessionQueue, videoQueue or the main queue as noted,
/// so sharing the instance across those queues is safe.
final class CameraController: NSObject, ObservableObject, @unchecked Sendable {
    enum Status { case starting, running, denied, unavailable }

    @Published private(set) var status: Status = .starting
    /// Smoothed document outline in upright (portrait) normalized coordinates.
    @Published private(set) var liveQuad: Quad?
    @Published private(set) var isCapturing = false
    @Published private(set) var torchOn = false

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "DocScanner.camera.session")
    private let videoQueue = DispatchQueue(label: "DocScanner.camera.video")
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private var device: AVCaptureDevice?
    private var isConfigured = false
    private var photoContinuation: CheckedContinuation<UIImage?, Never>?

    // Live detection state, touched only on videoQueue.
    private var lastDetection = Date.distantPast
    private var recentQuads: [Quad] = []
    private var misses = 0

    // MARK: - Lifecycle

    @MainActor
    func start() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                status = .denied
                return
            }
        default:
            status = .denied
            return
        }
        sessionQueue.async { [weak self] in self?.configureAndRun() }
    }

    func stop() {
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func configureAndRun() {
        if !isConfigured {
            guard configure() else {
                DispatchQueue.main.async { self.status = .unavailable }
                return
            }
            isConfigured = true
        }
        if !session.isRunning { session.startRunning() }
        DispatchQueue.main.async { self.status = .running }
    }

    private func configure() -> Bool {
        // Multi-lens cameras switch to the ultra wide automatically for close-up
        // (macro) focus, which keeps small documents sharp.
        let types: [AVCaptureDevice.DeviceType] = [.builtInTripleCamera, .builtInDualWideCamera, .builtInWideAngleCamera]
        guard let device = types.lazy.compactMap({ AVCaptureDevice.default($0, for: .video, position: .back) }).first,
              let input = try? AVCaptureDeviceInput(device: device) else { return false }

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo

        guard session.canAddInput(input), session.canAddOutput(photoOutput), session.canAddOutput(videoOutput) else { return false }
        session.addInput(input)
        session.addOutput(photoOutput)
        photoOutput.maxPhotoQualityPrioritization = .quality

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        session.addOutput(videoOutput)

        // Photos come out portrait. Video frames stay in sensor orientation and
        // are rotated for Vision instead (see captureOutput).
        if let connection = photoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }

        if (try? device.lockForConfiguration()) != nil {
            if let wide = device.virtualDeviceSwitchOverVideoZoomFactors.first {
                // Virtual devices start on the ultra wide; zoom to the normal 1x lens.
                device.videoZoomFactor = CGFloat(truncating: wide)
            }
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
            device.unlockForConfiguration()
        }
        self.device = device
        return true
    }

    // MARK: - Controls

    func toggleTorch() {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.device, device.hasTorch, (try? device.lockForConfiguration()) != nil else { return }
            let on = device.torchMode != .on
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
            DispatchQueue.main.async { self.torchOn = on }
        }
    }

    @MainActor
    func capturePhoto() async -> UIImage? {
        guard status == .running, !isCapturing else { return nil }
        isCapturing = true
        defer { isCapturing = false }
        return await withCheckedContinuation { continuation in
            sessionQueue.async {
                self.photoContinuation = continuation
                let settings = AVCapturePhotoSettings()
                settings.photoQualityPrioritization = .quality
                self.photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    // MARK: - Live detection

    /// Averages the last few detections so the outline doesn't jitter, and
    /// keeps showing it briefly when a frame misses.
    private func smooth(_ quad: Quad?) -> Quad? {
        if let quad {
            misses = 0
            if let last = recentQuads.last, last.maxCornerDistance(to: quad) > 0.12 {
                recentQuads.removeAll() // the page moved; don't blend old and new
            }
            recentQuads.append(quad)
            if recentQuads.count > 4 { recentQuads.removeFirst() }
        } else {
            misses += 1
            if misses > 3 { recentQuads.removeAll() }
        }
        return Quad.average(recentQuads)
    }
}

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = Date()
        guard now.timeIntervalSince(lastDetection) > 0.1,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastDetection = now
        // The back camera sensor is landscape; .right rotates it to portrait.
        let quad = smooth(EdgeDetector.detect(pixelBuffer: buffer, orientation: .right))
        DispatchQueue.main.async { self.liveQuad = quad }
    }
}

extension CameraController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let image = error == nil ? photo.fileDataRepresentation().flatMap(UIImage.init(data:)) : nil
        sessionQueue.async {
            self.photoContinuation?.resume(returning: image)
            self.photoContinuation = nil
        }
    }
}
