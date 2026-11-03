import SwiftUI

@main
struct DocScannerApp: App {
    @StateObject private var store = ScanStore()

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(store)
        }
    }
}
