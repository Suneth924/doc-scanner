import SwiftUI

/// Starts the built-in web server and shows the address to open on a PC or Mac.
struct TransferView: View {
    @EnvironmentObject private var store: ScanStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var server = TransferServer()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Wi‑Fi Transfer", isOn: Binding(
                        get: { server.isRunning },
                        set: { $0 ? startServer() : server.stop() }
                    ))
                } footer: {
                    Text("Keep this screen open while transferring. iOS pauses the server when the app is in the background.")
                }

                if server.isRunning {
                    Section("Open one of these in a browser on your PC or Mac") {
                        if server.addresses.isEmpty {
                            Text("No network found. Connect to Wi‑Fi or Tailscale.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(server.addresses, id: \.self) { ip in
                            let url = "http://\(ip):\(server.port)"
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(url).font(.body.monospaced()).textSelection(.enabled)
                                    Text(ip.hasPrefix("100.") ? "Tailscale" : "Wi‑Fi")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button { UIPasteboard.general.string = url } label: {
                                    Image(systemName: "doc.on.doc")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }

                if let error = server.errorMessage {
                    Section { Text(error).foregroundStyle(.red) }
                }

                Section("Other ways to send scans") {
                    Label("Mac: open a scan, tap Share, then AirDrop", systemImage: "airplayaudio")
                    Label("NAS: Share › Save to Files › your NAS (add it in Files › Connect to Server)", systemImage: "externaldrive.connected.to.line.below")
                }
                .font(.callout)
            }
            .navigationTitle("Send to computer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear(perform: startServer)
            .onDisappear { server.stop() }
        }
    }

    private func startServer() {
        let store = store
        server.listItems = {
            DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    store.documents.map { .init(id: $0.id, name: $0.name, pages: $0.pageCount, date: $0.createdAt) }
                }
            }
        }
        server.makePDF = { id in
            let doc: ScanDocument? = DispatchQueue.main.sync {
                MainActor.assumeIsolated { store.documents.first { $0.id == id } }
            }
            guard let doc else { return nil }
            let data = PDFExporter.makePDF(from: store.filteredPages(for: doc))
            return ("\(doc.exportFileName).pdf", data)
        }
        server.start()
    }
}
