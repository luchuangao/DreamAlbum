import SwiftUI
import UIKit

@MainActor enum CollageTransfer {
    static func load(_ ids: [String], service: any PhotoLibraryService, folder: URL, progress: @escaping (Double) -> Void) async throws -> [CollageLayer] {
        var layers: [CollageLayer] = []
        do {
            for (i, id) in ids.enumerated() {
                try Task.checkCancellation()
                let data = try await service.imageData(id: id) { fraction in progress((Double(i)+fraction)/Double(max(ids.count, 1))) }
                let layer = try await Task.detached { try CollageImportSession.writeAsset(data, into: folder) }.value
                layers.append(layer); try Task.checkCancellation()
                progress(Double(i+1)/Double(max(ids.count, 1)))
            }
            return layers
        } catch {
            for layer in layers { if let file = layer.file { try? FileManager.default.removeItem(at: folder.appendingPathComponent(file)) } }
            throw error
        }
    }
}

struct CollageAddPhotosView: View {
    @ObservedObject var model: CollageEditorModel
    @EnvironmentObject private var library: PhotoLibraryStore
    @EnvironmentObject private var store: DreamStore
    @Environment(\.dismiss) private var dismiss
    let replacing: Bool
    @State private var ids: [String] = []
    @State private var busy = false
    @State private var progress = 0.0
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    private func c(_ zh: String, _ en: String) -> String { AlbumCopy.pick(store.appLanguage, zh, en) }
    var body: some View {
        CollagePhotoPicker(groupID: model.document.sourceGroupID, selection: $ids, limit: 1...(replacing ? 1 : max(1, model.document.kind.limits.upperBound-model.document.photoCount)), title: c("选择照片", "Choose photos"), onConfirm: add)
            .disabled(busy).overlay { if busy { ProgressView(value: progress).padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(c("取消", "Cancel")) { task?.cancel(); dismiss() } } }
            .onDisappear { task?.cancel() }
            .alert(c("图片加载失败", "Could not load photos"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button(c("重试", "Retry"), action: add); Button(c("取消", "Cancel"), role: .cancel) { } } message: { Text(error ?? "") }
    }
    private func add() {
        guard !busy else { return }; busy = true
        let selection = model.selection
        task = Task {
            defer { busy = false }
            do {
                let items = try await CollageTransfer.load(ids, service: library.service, folder: model.store.directory(model.document.id)) { progress = $0 }
                try Task.checkCancellation()
                model.apply { doc in
                    if replacing, let selection, let i = doc.layers.firstIndex(where: { $0.id == selection }), let first = items.first {
                        let old = doc.layers[i]
                        guard !old.locked else { return }
                        var new = first; new.id = old.id; new.x = old.x; new.y = old.y; new.width = old.width; new.height = old.height; new.rotation = old.rotation; new.label = old.label
                        doc.layers[i] = new
                    } else {
                        doc.layers += items
                        if doc.kind == .freeform && !doc.hasFreeLayout { doc.arrangeFreeLayers() }
                    }
                }
                dismiss()
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }
}

struct CollageAdjustKindView: View {
    @ObservedObject var model: CollageEditorModel
    let kind: CollageKind
    @EnvironmentObject private var library: PhotoLibraryStore
    @EnvironmentObject private var store: DreamStore
    @Environment(\.dismiss) private var dismiss
    @State private var keep: Set<UUID> = []
    @State private var adding = false
    @State private var ids: [String] = []
    @State private var busy = false
    @State private var progress = 0.0
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    private func c(_ zh: String, _ en: String) -> String { AlbumCopy.pick(store.appLanguage, zh, en) }
    var body: some View {
        Form {
            Section {
                Text(c("已选 \(keep.count+ids.count) 张 · 需要 \(kind.limits.lowerBound)–\(kind.limits.upperBound) 张", "\(keep.count+ids.count) selected · choose \(kind.limits.lowerBound)–\(kind.limits.upperBound)"))
                ForEach(model.document.layers.filter(\.isPhoto)) { layer in
                    Toggle(isOn: Binding(get: { keep.contains(layer.id) }, set: { if $0 { keep.insert(layer.id) } else { keep.remove(layer.id) } })) {
                        LocalCollageThumbnail(url: model.store.directory(model.document.id).appendingPathComponent(layer.file ?? ""))
                            .frame(width: 70, height: 70)
                    }
                }
                Button(c("添加照片", "Add photos")) { adding = true }.disabled(keep.count+ids.count >= kind.limits.upperBound)
                if !ids.isEmpty { Text(c("新增 \(ids.count) 张", "\(ids.count) new photos")); Button(c("清除新增选择", "Clear new selection")) { ids = [] } }
                if busy { ProgressView(value: progress) }
                if let error { Text(error).foregroundStyle(.red) }
            }
        }.disabled(busy).navigationTitle(kind.title(store.appLanguage))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(c("取消", "Cancel")) { task?.cancel(); dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(c("应用", "Apply"), action: apply).disabled(!kind.limits.contains(keep.count+ids.count) || busy) }
            }
            .sheet(isPresented: $adding) { NavigationStack { CollagePhotoPicker(groupID: model.document.sourceGroupID, selection: $ids, limit: 1...max(1, kind.limits.upperBound-keep.count), title: c("添加照片", "Add photos")) { adding = false }.toolbar { ToolbarItem(placement: .cancellationAction) { Button(c("取消", "Cancel")) { adding = false } } } } }
            .onAppear { keep = Set(model.document.layers.filter(\.isPhoto).map(\.id)) }
            .onDisappear { task?.cancel() }
    }
    private func apply() {
        guard !busy else { return }; busy = true
        let selectedIDs = ids, keptIDs = keep
        task = Task {
            defer { busy = false }
            do {
                let new = try await CollageTransfer.load(selectedIDs, service: library.service, folder: model.store.directory(model.document.id)) { progress = $0 }
                try Task.checkCancellation()
                model.apply { doc in
                    doc.layers.removeAll { $0.isPhoto && !keptIDs.contains($0.id) }
                    doc.layers += new; doc.setKind(kind)
                    if kind == .freeform && !doc.hasFreeLayout { doc.arrangeFreeLayers() }
                }
                model.selection = nil; dismiss()
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }
}

struct LocalCollageThumbnail: View {
    let url: URL
    @State private var image: UIImage?
    var body: some View {
        Group { if let image { Image(uiImage: image).resizable().scaledToFit() } else { Image(systemName: "photo") } }
            .task(id: url) { image = await Task.detached { try? CollageRenderer.load(url, maxPixel: 200) }.value }
    }
}

struct CollageExportView: View {
    @ObservedObject var model: CollageEditorModel
    @EnvironmentObject private var library: PhotoLibraryStore
    @EnvironmentObject private var store: DreamStore
    @Environment(\.albumTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var format = CollageFileFormat.jpeg
    @State private var quality = 2048
    @State private var urls: [URL] = []
    @State private var busy = false
    @State private var saving = false
    @State private var progress = 0.0
    @State private var error: String?
    @State private var status: String?
    @State private var task: Task<Void, Never>?
    @State private var sharing = false
    @State private var attaching = false
    @State private var dreamID: UUID?
    @State private var title = ""
    private func c(_ zh: String, _ en: String) -> String { AlbumCopy.pick(store.appLanguage, zh, en) }
    var body: some View {
        Form {
            Section {
                Picker(c("格式", "Format"), selection: $format) { ForEach(CollageFileFormat.allCases) { Text($0.rawValue).tag($0) } }
                if model.document.kind != .strip { Picker(c("长边像素", "Long-edge pixels"), selection: $quality) { Text("2048 px").tag(2048); Text("4096 px").tag(4096) } }
                else { Text(c("宽 1440px；横图以高 1440px 拼接。", "1440px wide, or 1440px high for horizontal collages.")).font(.caption) }
                if model.pages.count > 1 { Text(c("将分为 \(model.pages.count) 张保存，每页最长 16000px。", "Exports \(model.pages.count) pages, up to 16000px each.")) }
            }.disabled(busy || saving)
            Section {
                if busy {
                    ProgressView(value: progress)
                    Button(c("取消生成", "Cancel export")) { task?.cancel() }
                } else {
                    Button(action: generate) { Text(urls.isEmpty ? c("生成拼图", "Generate collage") : c("重新生成", "Generate again")).frame(maxWidth: .infinity, minHeight: 44).foregroundStyle(.white) }
                        .buttonStyle(.borderedProminent).tint(theme.accent).disabled(saving).accessibilityIdentifier("collage.export.generate")
                }
                if saving { ProgressView() }
                if let status { Text(status).foregroundStyle(theme.accent).accessibilityIdentifier("collage.export.status") }
                if let error { Text(error).font(.caption).foregroundStyle(theme.destructive) }
            }
            if !urls.isEmpty && !busy {
                Section(c("成图", "Output")) {
                    Text(c("\(urls.count) 张图片", "\(urls.count) images"))
                    Button(c("保存到照片", "Save to Photos"), systemImage: "square.and.arrow.down") { saveToPhotos() }.accessibilityIdentifier("collage.export.photos")
                    Button(c("加入梦想画册", "Add to dream album"), systemImage: "book") { attaching = true }.accessibilityIdentifier("collage.export.album")
                    Button(c("分享", "Share"), systemImage: "square.and.arrow.up") { sharing = true }.accessibilityIdentifier("collage.export.share")
                }.disabled(saving)
            }
        }.scrollContentBackground(.hidden).background(AlbumBackground())
            .navigationTitle(c("导出拼图", "Export collage")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(c("完成", "Done")) { task?.cancel(); dismiss() }.disabled(saving) } }
            .interactiveDismissDisabled(saving)
            .sheet(isPresented: $sharing) { CollageShareSheet(urls: urls) }
            .sheet(isPresented: $attaching) { NavigationStack { attachForm } }
            .onChange(of: format) { _, _ in invalidate() }
            .onChange(of: quality) { _, _ in invalidate() }
            .onDisappear { if !sharing && !attaching { task?.cancel(); CollageRenderer.cleanExport(urls) } }
    }
    private var attachForm: some View {
        Form {
            Picker(c("目标画册", "Destination"), selection: $dreamID) {
                Text(c("新建梦想画册", "New dream album")).tag(Optional<UUID>.none)
                ForEach(store.activeDreams) { Text($0.title).tag(Optional($0.id)) }
            }
            if dreamID == nil { TextField(c("画册名称", "Album name"), text: $title).onChange(of: title) { _, value in title = String(value.prefix(12)) } }
            Button(c("加入梦想画册", "Add to dream album")) {
                do { try model.store.attach(urls, to: dreamID, title: title, dreams: store); status = c("已加入画册", "Added to album"); attaching = false }
                catch { self.error = error.localizedDescription; attaching = false }
            }.disabled(dreamID == nil && (title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.canCreateDream))
        }.navigationTitle(c("加入梦想画册", "Add to dream album"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(c("取消", "Cancel")) { attaching = false } } }
    }
    private func invalidate() { CollageRenderer.cleanExport(urls); urls = []; status = nil; error = nil }
    private func generate() {
        guard !busy && !saving else { return }; status = nil; error = nil; busy = true; progress = 0
        let doc = model.document, folder = model.store.directory(doc.id), chosenFormat = format, edge = quality
        task = Task {
            defer { busy = false }
            let worker = Task.detached(priority: .userInitiated) { try await CollageRenderer.export(doc, root: folder, longEdge: edge, fileFormat: chosenFormat) { value in Task { @MainActor in progress = value } } }
            do {
                let files = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                if Task.isCancelled { CollageRenderer.cleanExport(files); return }
                CollageRenderer.cleanExport(urls); urls = files
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }
    private func saveToPhotos() {
        guard !saving else { return }; saving = true; error = nil
        Task {
            defer { saving = false }
            do { try await library.service.saveGeneratedImages(urls); status = c("已保存到照片", "Saved to Photos") }
            catch { self.error = error.localizedDescription }
        }
    }
}

struct CollageShareSheet: UIViewControllerRepresentable {
    let urls: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: urls, applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
}
