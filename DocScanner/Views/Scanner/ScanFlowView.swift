import PhotosUI
import SwiftUI

/// The scanning screen: live camera with edge detection, then a corner
/// editor for each captured page. Pages can also be imported from Photos.
struct ScanFlowView: View {
    let onFinish: ([ScannedPage]) -> Void
    let onCancel: () -> Void

    @StateObject private var camera = CameraController()
    @State private var pages: [ScannedPage] = []
    @State private var review: ReviewItem?
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isProcessing = false
    @State private var confirmingDiscard = false

    private struct ReviewItem: Identifiable {
        let id = UUID()
        let image: UIImage
        let quad: Quad
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if camera.status == .running {
                CameraPreview(session: camera.session, quad: camera.liveQuad)
                    .ignoresSafeArea()
            } else {
                unavailableMessage
            }

            VStack {
                topBar
                Spacer()
                hint
                bottomBar
            }
            .padding()

            if isProcessing {
                ProgressView().controlSize(.large).tint(.white)
            }
        }
        .preferredColorScheme(.dark)
        .task { await camera.start() }
        .onDisappear { camera.stop() }
        .onChange(of: pickerItems) { _, items in importPhotos(items) }
        .fullScreenCover(item: $review) { item in
            CropEditorView(
                image: item.image,
                initialQuad: item.quad,
                title: "Page \(pages.count + 1)",
                confirmTitle: "Keep",
                cancelTitle: "Retake",
                onDone: { quad in
                    pages.append(ScannedPage(source: item.image, quad: quad))
                    review = nil
                },
                onCancel: { review = nil }
            )
        }
        .confirmationDialog("Discard \(pages.count) scanned page\(pages.count == 1 ? "" : "s")?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { onCancel() }
            Button("Keep Scanning", role: .cancel) {}
        }
    }

    // MARK: - Pieces

    private var topBar: some View {
        HStack {
            Button("Cancel") {
                if pages.isEmpty { onCancel() } else { confirmingDiscard = true }
            }
            Spacer()
            if camera.status == .running {
                Button { camera.toggleTorch() } label: {
                    Image(systemName: camera.torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(camera.torchOn ? "Turn off light" : "Turn on light")
            }
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private var hint: some View {
        if camera.status == .running {
            Text(camera.liveQuad == nil ? "Looking for a document…" : "Document found. Tap to capture.")
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.black.opacity(0.55), in: Capsule())
                .foregroundStyle(.white)
                .padding(.bottom, 8)
        }
    }

    private var bottomBar: some View {
        HStack {
            PhotosPicker(selection: $pickerItems, matching: .images) {
                Image(systemName: "photo.on.rectangle")
                    .font(.title2)
                    .frame(width: 60, height: 60)
            }
            .accessibilityLabel("Import from Photos")

            Spacer()

            Button(action: capture) {
                ZStack {
                    Circle().stroke(.white, lineWidth: 4).frame(width: 74, height: 74)
                    Circle().fill(.white).frame(width: 62, height: 62)
                }
            }
            .disabled(camera.status != .running || camera.isCapturing || isProcessing)
            .accessibilityLabel("Capture page")

            Spacer()

            Button { onFinish(pages) } label: {
                Text(pages.isEmpty ? "Done" : "Done (\(pages.count))")
                    .font(.headline)
                    .frame(minWidth: 60, minHeight: 60)
            }
            .disabled(pages.isEmpty)
        }
        .foregroundStyle(.white)
    }

    private var unavailableMessage: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.fill").font(.largeTitle)
            switch camera.status {
            case .denied:
                Text("Camera access is off. Allow it in Settings, or import a photo instead.")
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            case .unavailable:
                Text("No camera available. Import a photo instead.")
            default:
                ProgressView()
            }
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(.white)
        .padding(32)
    }

    // MARK: - Actions

    private func capture() {
        Task {
            guard let photo = await camera.capturePhoto() else { return }
            let liveQuad = camera.liveQuad
            isProcessing = true
            // Detect again on the full-resolution still: it is sharper than the
            // video frame, so the corners land more precisely.
            let (image, detected) = await Task.detached { () -> (UIImage, Quad?) in
                let upright = photo.normalizedOrientation()
                return (upright, EdgeDetector.detect(in: upright))
            }.value
            isProcessing = false
            review = ReviewItem(image: image, quad: detected ?? liveQuad ?? .full)
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        isProcessing = true
        Task {
            var imported: [ScannedPage] = []
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { continue }
                let page = await Task.detached { () -> ScannedPage in
                    let upright = image.normalizedOrientation()
                    return ScannedPage(source: upright, quad: EdgeDetector.detect(in: upright) ?? .full)
                }.value
                imported.append(page)
            }
            pickerItems = []
            isProcessing = false
            if imported.count == 1, let page = imported.first {
                // A single photo goes through the corner editor like a capture.
                review = ReviewItem(image: page.source, quad: page.quad)
            } else {
                // Several photos are added straight away; edges can be adjusted later.
                pages += imported
            }
        }
    }
}
