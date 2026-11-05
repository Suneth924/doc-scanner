import CoreGraphics

/// The four corners of a document in normalized image coordinates
/// (0...1 on each axis, origin at the top-left of the upright image).
struct Quad: Codable, Hashable {
    var topLeft: CGPoint
    var topRight: CGPoint
    var bottomRight: CGPoint
    var bottomLeft: CGPoint

    /// The whole image, i.e. no crop.
    static let full = Quad(
        topLeft: CGPoint(x: 0, y: 0),
        topRight: CGPoint(x: 1, y: 0),
        bottomRight: CGPoint(x: 1, y: 1),
        bottomLeft: CGPoint(x: 0, y: 1)
    )

    enum Corner: CaseIterable {
        case topLeft, topRight, bottomRight, bottomLeft
    }

    enum Edge: CaseIterable {
        case top, right, bottom, left

        var corners: (Corner, Corner) {
            switch self {
            case .top: (.topLeft, .topRight)
            case .right: (.topRight, .bottomRight)
            case .bottom: (.bottomRight, .bottomLeft)
            case .left: (.bottomLeft, .topLeft)
            }
        }
    }

    subscript(corner: Corner) -> CGPoint {
        get {
            switch corner {
            case .topLeft: topLeft
            case .topRight: topRight
            case .bottomRight: bottomRight
            case .bottomLeft: bottomLeft
            }
        }
        set {
            switch corner {
            case .topLeft: topLeft = newValue
            case .topRight: topRight = newValue
            case .bottomRight: bottomRight = newValue
            case .bottomLeft: bottomLeft = newValue
            }
        }
    }

    /// Corners in clockwise order starting at the top-left.
    var corners: [CGPoint] { [topLeft, topRight, bottomRight, bottomLeft] }

    func midpoint(of edge: Edge) -> CGPoint {
        let (a, b) = edge.corners
        return CGPoint(x: (self[a].x + self[b].x) / 2, y: (self[a].y + self[b].y) / 2)
    }

    /// Area as a fraction of the image (shoelace formula).
    var area: CGFloat {
        let p = corners
        var sum: CGFloat = 0
        for i in 0..<4 {
            let a = p[i], b = p[(i + 1) % 4]
            sum += a.x * b.y - b.x * a.y
        }
        return abs(sum) / 2
    }

    /// A perspective correction only makes sense for a convex, non-degenerate quad.
    var isConvex: Bool {
        let p = corners
        var sign: CGFloat = 0
        for i in 0..<4 {
            let a = p[i], b = p[(i + 1) % 4], c = p[(i + 2) % 4]
            let cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
            if abs(cross) < 1e-6 { return false }
            if sign == 0 {
                sign = cross
            } else if (cross > 0) != (sign > 0) {
                return false
            }
        }
        return area > 0.01
    }

    /// The largest distance between matching corners of two quads.
    func maxCornerDistance(to other: Quad) -> CGFloat {
        zip(corners, other.corners).map { hypot($0.x - $1.x, $0.y - $1.y) }.max() ?? 0
    }

    /// Corner-wise mean, used to smooth the live camera outline.
    static func average(_ quads: [Quad]) -> Quad? {
        guard !quads.isEmpty else { return nil }
        let n = CGFloat(quads.count)
        var result = Quad(topLeft: .zero, topRight: .zero, bottomRight: .zero, bottomLeft: .zero)
        for corner in Corner.allCases {
            let x = quads.reduce(0) { $0 + $1[corner].x } / n
            let y = quads.reduce(0) { $0 + $1[corner].y } / n
            result[corner] = CGPoint(x: x, y: y)
        }
        return result
    }

    func hash(into hasher: inout Hasher) {
        for p in corners {
            hasher.combine(p.x)
            hasher.combine(p.y)
        }
    }
}
