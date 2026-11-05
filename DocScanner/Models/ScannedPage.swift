import UIKit

/// A freshly captured or imported page: the full uncropped photo plus the
/// document corners to crop it to.
struct ScannedPage {
    var source: UIImage
    var quad: Quad
}
