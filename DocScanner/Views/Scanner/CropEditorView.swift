import SwiftUI

/// Lets the user drag the four corners (or the edges) of a detected document
/// to fit it exactly. A magnifier shows what's under the finger while dragging.
struct CropEditorView: View {
    let image: UIImage
    let title: String
    let confirmTitle: String
    let cancelTitle: String
    let onDone: (Quad) -> Void
    let onCancel: () -> Void

    @State private var quad: Quad
    @State private var dragStart: Quad?
    @State private var magnified: CGPoint? // normalized point shown in the loupe
    @State private var isDetecting = false

    private let canvasSpace = "cropCanvas"
    private let loupeSize: CGFloat = 120
    private let loupeZoom: CGFloat = 2.5

    init(
        image: UIImage,
        initialQuad: Quad,
        title: String = "Adjust Edges",
        confirmTitle: String = "Done",
        cancelTitle: String = "Cancel",
        onDone: @escaping (Quad) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.image = image
        self.title = title
        self.confirmTitle = confirmTitle
        self.cancelTitle = cancelTitle
        self.onDone = onDone
        self.onCancel = onCancel
        _quad = State(initialValue: initialQuad)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let rect = fittedRect(in: geo.size)
                ZStack(alignment: .topLeading) {
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)

                    overlay(in: rect)

                    ForEach(Quad.Edge.allCases, id: \.self) { edge in
                        edgeHandle(edge, in: rect)
                    }
                    ForEach(Quad.Corner.allCases, id: \.self) { corner in
                        cornerHandle(corner, in: rect)
                    }

                    if let magnified {
                        loupe(at: magnified, in: rect, canvas: geo.size)
                    }
                }
                .coordinateSpace(name: canvasSpace)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar, .bottomBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(cancelTitle, action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmTitle) { onDone(quad) }
                        .bold()
                        .disabled(!quad.isConvex)
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        autoDetect()
                    } label: {
                        Label("Auto", systemImage: "wand.and.stars")
                    }
                    .disabled(isDetecting)
                    Spacer()
                    if !quad.isConvex {
                        Text("Corners overlap").font(.footnote).foregroundStyle(.red)
                        Spacer()
                    }
                    Button {
                        withAnimation(.snappy) { quad = .full }
                    } label: {
                        Label("Full Page", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Geometry

    /// Where the image is drawn: aspect-fit with room for the handles.
    private func fittedRect(in size: CGSize) -> CGRect {
        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: 28, dy: 28)
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else { return bounds }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let fitted = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: bounds.midX - fitted.width / 2,
            y: bounds.midY - fitted.height / 2,
            width: fitted.width,
            height: fitted.height
        )
    }

    private func viewPoint(_ p: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + p.x * rect.width, y: rect.minY + p.y * rect.height)
    }

    // MARK: - Drawing

    private func overlay(in rect: CGRect) -> some View {
        let points = quad.corners.map { viewPoint($0, in: rect) }
        let shape = Path { path in
            path.addLines(points)
            path.closeSubpath()
        }
        let color: Color = quad.isConvex ? .accentColor : .red
        return ZStack {
            // Dim everything outside the page.
            Path { path in
                path.addRect(rect)
                path.addLines(points)
                path.closeSubpath()
            }
            .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
            shape.fill(color.opacity(0.12))
            shape.stroke(color, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
        }
        .allowsHitTesting(false)
    }

    private func cornerHandle(_ corner: Quad.Corner, in rect: CGRect) -> some View {
        let color: Color = quad.isConvex ? .accentColor : .red
        return ZStack {
            Circle().fill(.white.opacity(0.25)).frame(width: 30, height: 30)
            Circle().stroke(color, lineWidth: 3).frame(width: 30, height: 30)
        }
        .frame(width: 48, height: 48)
        .contentShape(Rectangle())
        .position(viewPoint(quad[corner], in: rect))
        .gesture(drag(moving: [corner], in: rect, magnify: corner))
        .accessibilityLabel("Corner")
    }

    private func edgeHandle(_ edge: Quad.Edge, in rect: CGRect) -> some View {
        let (a, b) = edge.corners
        let start = viewPoint(quad[a], in: rect)
        let end = viewPoint(quad[b], in: rect)
        let angle = Angle(radians: atan2(end.y - start.y, end.x - start.x))
        return Capsule()
            .fill(.white)
            .overlay(Capsule().stroke(Color.accentColor, lineWidth: 2))
            .frame(width: 26, height: 8)
            .rotationEffect(angle)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .position(viewPoint(quad.midpoint(of: edge), in: rect))
            .gesture(drag(moving: [a, b], in: rect, magnify: nil))
            .accessibilityLabel("Edge")
    }

    private func loupe(at point: CGPoint, in rect: CGRect, canvas: CGSize) -> some View {
        let p = viewPoint(point, in: rect)
        // Show the loupe in the top corner away from the finger.
        let x = p.x < canvas.width / 2 ? canvas.width - loupeSize / 2 - 16 : loupeSize / 2 + 16
        return Image(uiImage: image)
            .resizable()
            .frame(width: rect.width * loupeZoom, height: rect.height * loupeZoom)
            .offset(
                x: loupeSize / 2 - (p.x - rect.minX) * loupeZoom,
                y: loupeSize / 2 - (p.y - rect.minY) * loupeZoom
            )
            .frame(width: loupeSize, height: loupeSize, alignment: .topLeading)
            .background(Color.black)
            .clipShape(Circle())
            .overlay {
                ZStack {
                    Rectangle().fill(Color.accentColor).frame(width: 1, height: 22)
                    Rectangle().fill(Color.accentColor).frame(width: 22, height: 1)
                }
            }
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .shadow(radius: 6)
            .position(x: x, y: loupeSize / 2 + 16)
            .allowsHitTesting(false)
    }

    // MARK: - Interaction

    private func drag(moving corners: [Quad.Corner], in rect: CGRect, magnify: Quad.Corner?) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(canvasSpace))
            .onChanged { value in
                if dragStart == nil { dragStart = quad }
                guard let start = dragStart, rect.width > 0, rect.height > 0 else { return }
                let dx = value.translation.width / rect.width
                let dy = value.translation.height / rect.height
                var updated = start
                for corner in corners {
                    let p = start[corner]
                    updated[corner] = CGPoint(x: min(max(p.x + dx, 0), 1), y: min(max(p.y + dy, 0), 1))
                }
                quad = updated
                magnified = magnify.map { updated[$0] }
            }
            .onEnded { _ in
                dragStart = nil
                magnified = nil
            }
    }

    private func autoDetect() {
        isDetecting = true
        let image = image
        Task {
            let detected = await Task.detached { EdgeDetector.detect(in: image) }.value
            isDetecting = false
            withAnimation(.snappy) { quad = detected ?? .full }
        }
    }
}
