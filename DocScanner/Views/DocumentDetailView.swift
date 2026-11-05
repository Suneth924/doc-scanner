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
    @State private var currentPage = 0
    @State private var cropTarget: CropTarget?

    private struct CropTarget: Identifiable {
        let id = UUID()
        let index: Int
        let image: UIImage
        let quad: Quad
    }

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
            TabView(selection: $currentPage) {
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

            HStack(spacing: 12) {
                Button { editCrop(doc) } label: {
                    Label("Adjust Edges", systemImage: "crop")
                        .labelStyle(.iconOnly)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.bordered)
                .disabled(pages.isEmpty || isWorking)
                .accessibilityLabel("Adjust edges of this page")

                Picker("Filter", selection: filterBinding(doc)) {
                    ForEach(ScanFilter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
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
                    Button("Adjust edges", systemImage: "crop") { editCrop(doc) }
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
            ScanFlowView { newPages in
                addingPages = false
                Task { await store.appendPages(newPages, to: doc) }
            } onCancel: {
                addingPages = false
            }
        }
        .fullScreenCover(item: $cropTarget) { target in
            CropEditorView(
                image: target.image,
                initialQuad: target.quad,
                title: "Page \(target.index + 1)",
                onDone: { quad in
                    cropTarget = nil
                    isWorking = true
                    Task {
                        await store.updateCrop(quad, page: target.index, of: doc)
                        isWorking = false
                    }
                },
                onCancel: { cropTarget = nil }
            )
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

    /// Opens the corner editor on the uncropped photo of the visible page.
    private func editCrop(_ doc: ScanDocument) {
        let index = min(currentPage, doc.pageCount - 1)
        guard index >= 0 else { return }
        let store = store
        isWorking = true
        Task {
            let image = await Task.detached { store.sourceImage(for: doc, index: index)?.normalizedOrientation() }.value
            isWorking = false
            guard let image else { return }
            cropTarget = CropTarget(index: index, image: image, quad: doc.crop(at: index))
        }
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
