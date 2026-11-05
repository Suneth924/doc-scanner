import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var store: ScanStore
    @State private var showingCamera = false
    @State private var showingTransfer = false
    @State private var path: [ScanDocument] = []

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if store.documents.isEmpty {
                    ContentUnavailableView {
                        Label("No scans yet", systemImage: "doc.viewfinder")
                    } description: {
                        Text("Tap Scan to capture your first document.")
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(store.documents) { doc in
                                NavigationLink(value: doc) { DocumentCard(doc: doc) }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button("Delete", systemImage: "trash", role: .destructive) { store.delete(doc) }
                                    }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Scans")
            .navigationDestination(for: ScanDocument.self) { doc in
                DocumentDetailView(docID: doc.id)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingTransfer = true } label: {
                        Label("Wi‑Fi Transfer", systemImage: "wifi")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button { showingCamera = true } label: {
                    Label("Scan", systemImage: "camera.viewfinder")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding()
            }
            .fullScreenCover(isPresented: $showingCamera) {
                ScanFlowView { pages in
                    showingCamera = false
                    Task {
                        if let doc = await store.add(pages: pages) { path = [doc] }
                    }
                } onCancel: {
                    showingCamera = false
                }
            }
            .sheet(isPresented: $showingTransfer) { TransferView() }
        }
    }
}

private struct DocumentCard: View {
    @EnvironmentObject private var store: ScanStore
    let doc: ScanDocument
    @State private var thumb: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemBackground))
                if let thumb {
                    Image(uiImage: thumb).resizable().scaledToFit()
                } else {
                    ProgressView()
                }
            }
            .aspectRatio(3 / 4, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.08), radius: 3, y: 1)

            Text(doc.name).font(.subheadline.weight(.semibold)).lineLimit(1)
            Text("\(doc.pageCount) page\(doc.pageCount == 1 ? "" : "s")")
                .font(.caption).foregroundStyle(.secondary)
        }
        .task(id: doc) {
            let store = store
            let doc = doc
            thumb = await Task.detached { store.thumbnail(for: doc) }.value
        }
    }
}
