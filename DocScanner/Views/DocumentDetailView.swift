import SwiftUI

struct DocumentDetailView: View {
    @EnvironmentObject private var store: ScanStore
    @Environment(\.dismiss) private var dismiss
    let docID: UUID

    @State private var pages: [UIImage] = []
    @State private var isWorking = false
    @State private var shareItems: ShareItems?
    @State private var renaming = false
    @State private var newName = ""
    @State private var addingPages = false

    private var doc: ScanDocument? { store.documents.first { $0.id == docID } }

    var body: some View {
        if let doc {
            content(doc)
        } else {
            ContentUnavailableView("Scan deleted", systemImage: "trash")
        }
    }

    private func content(_ doc: ScanDocument) -> some View {
        VStack(spacing: 0) {
            TabView {
                ForEach(pages.indices, id: \.self) { i in
                    Image(uiImage: pages[i])
                        .resizable()
                        .scaledToFit()
                        .padding()
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .background(Color(.secondarySystemBackground))
            .overlay { if pages.isEmpty || isWorking { ProgressView() } }

            Picker("Filter", selection: filterBinding(doc)) {
                ForEach(ScanFilter.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding()
        }
        .navigationTitle(doc.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Share PDF", systemImage: "doc.richtext") { share(doc, asPDF: true) }
                    Button("Share JPEG", systemImage: "photo") { share(doc, asPDF: false) }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Rename", systemImage: "pencil") { newName = doc.name; renaming = true }
                    Button("Add pages", systemImage: "plus.viewfinder") { addingPages = true }
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        store.delete(doc)
                        dismiss()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task(id: doc) { await loadPages(doc) }
        .sheet(item: $shareItems) { ShareSheet(items: $0.urls).presentationDetents([.medium, .large]) }
        .alert("Rename scan", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Save") {
                var updated = doc
                let trimmed = newName.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { updated.name = trimmed; store.update(updated) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $addingPages) {
            DocumentCameraView { newPages in
                addingPages = false
                store.appendPages(newPages, to: doc)
            } onCancel: {
                addingPages = false
            }
            .ignoresSafeArea()
        }
    }

    private func filterBinding(_ doc: ScanDocument) -> Binding<ScanFilter> {
        Binding(
            get: { doc.filter },
            set: { newValue in
                var updated = doc
                updated.filter = newValue
                store.update(updated)
            }
        )
    }

    private func loadPages(_ doc: ScanDocument) async {
        isWorking = true
        let store = store
        pages = await Task.detached { store.filteredPages(for: doc) }.value
        isWorking = false
    }

    private func share(_ doc: ScanDocument, asPDF: Bool) {
        isWorking = true
        let store = store
        Task {
            let urls: [URL] = await Task.detached {
                asPDF ? [store.exportPDF(doc)].compactMap { $0 } : store.exportJPEGs(doc)
            }.value
            isWorking = false
            if !urls.isEmpty { shareItems = ShareItems(urls: urls) }
        }
    }
}
