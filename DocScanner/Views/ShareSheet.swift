import SwiftUI

/// System share sheet: AirDrop to a Mac, Save to Files (including a NAS over SMB), Mail, OneDrive, etc.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

struct ShareItems: Identifiable {
    let id = UUID()
    let urls: [URL]
}
