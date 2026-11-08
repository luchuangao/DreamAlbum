import SwiftUI
import Photos

struct NewCollageView: View {
    @EnvironmentObject private var library: PhotoLibraryStore
    @EnvironmentObject private var store: DreamStore
    @EnvironmentObject private var collages: CollageStore
    @Environment(\.albumTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    let groupID: String
    var preselected: [String] = []
    @State private var kind: CollageKind?
    @State private var ids: [String] = []
    @State private var created: CollageDocument?
    @StateObject private var importer = CollageImportSession()
    private func c(_ zh: String, _ en: String) -> String { AlbumCopy.pick(store.appLanguage, zh, en) }
    var body: some View {
        NavigationStack {
            Group {
                if let created { CollageEditor(document: created, workspace: collages, onClose: { dismiss() }) }
                else if let kind {
                    CollagePhotoPicker(groupID: groupID, selection: $ids, limit: kind.limits, title: kind.title(store.appLanguage)) {
                        importer.run(ids: ids, kind: kind, groupID: groupID, name: kind.title(store.appLanguage), language: store.appLanguage, service: library.service, store: collages) { created = $0 }
                    }
                    .disabled(importer.running)
                    .overlay { if importer.running { progressPanel } }
                    .safeAreaInset(edge: .bottom) {
                        if let error = importer.error {
                            VStack { Text(error).font(.caption).foregroundStyle(theme.destructive); Button(c("重试", "Retry")) { start(kind) } }.padding().background(theme.surface)
                        }
                    }
                    .toolbar { ToolbarItem(placement: .topBarLeading) { Button(c("样式", "Style")) { self.kind = nil }.disabled(importer.running) } }
                } else {
                    List {
                        ForEach(CollageKind.allCases) { value in
                            Button { kind = value } label: {
                                Label {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(value.title(store.appLanguage)).font(.headline)
                                        Text(c("\(value.limits.lowerBound)–\(value.limits.upperBound) 张照片", "\(value.limits.lowerBound)–\(value.limits.upperBound) photos")).font(.caption).foregroundStyle(theme.secondary)
                                    }.padding(.vertical, 8)
                                } icon: { Image(systemName: value.symbol).foregroundStyle(theme.accent).frame(width: 32) }
                            }.accessibilityIdentifier("collage.kind."+value.rawValue)
                        }.listRowBackground(theme.surface)
                    }.scrollContentBackground(.hidden).navigationTitle(c("制作拼图", "Create collage"))
                }
            }
            .background(AlbumBackground())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { if created == nil { ToolbarItem(placement: .cancellationAction) { Button(c("取消", "Cancel")) { importer.close(); dismiss() }.disabled(importer.running) } } }
        }
        .onAppear { ids = preselected }
        .onDisappear { importer.close() }
        .interactiveDismissDisabled(importer.running)
    }
    private func start(_ kind: CollageKind) {
        importer.run(ids: ids, kind: kind, groupID: groupID, name: kind.title(store.appLanguage), language: store.appLanguage, service: library.service, store: collages) { created = $0 }
    }
    private var progressPanel: some View {
        VStack(spacing: 16) {
            ProgressView(value: importer.progress).frame(width: 200)
            Text(c("正在保存素材…", "Saving photos…"))
            Button(c("取消", "Cancel")) { importer.close(); dismiss() }
        }.padding(24).background(theme.surface, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct CollagePhotoPicker: View {
    @EnvironmentObject private var library: PhotoLibraryStore
    @EnvironmentObject private var store: DreamStore
    @Environment(\.albumTheme) private var theme
    let groupID: String?
    @Binding var selection: [String]
    let limit: ClosedRange<Int>
    var title = ""
    var onConfirm: () -> Void
    @State private var photos: [LibraryPhoto] = []
    @State private var loading = true
    @State private var missing = false
    private func c(_ zh: String, _ en: String) -> String { AlbumCopy.pick(store.appLanguage, zh, en) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                Text(c("已选 \(selection.count) 张 · 需要 \(limit.lowerBound)–\(limit.upperBound) 张", "\(selection.count) selected · choose \(limit.lowerBound)–\(limit.upperBound)"))
                    .font(.subheadline).padding(.horizontal).accessibilityIdentifier("collage.photo.count")
                if missing { Text(c("原分组不可用。", "Source album unavailable.")).font(.caption).padding(.horizontal) }
                if loading { ProgressView().frame(maxWidth: .infinity).padding() }
                else if photos.isEmpty { ContentUnavailableView(c("暂无可访问照片", "No accessible photos"), systemImage: "photo") }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 95), spacing: 3)], spacing: 3) {
                    ForEach(photos) { photo in
                        Button {
                            if let i = selection.firstIndex(of: photo.id) { selection.remove(at: i) }
                            else if selection.count < limit.upperBound { selection.append(photo.id) }
                        } label: {
                            LibraryThumbnail(id: photo.id).aspectRatio(1, contentMode: .fit)
                                .overlay(alignment: .bottomTrailing) {
                                    Text(selection.firstIndex(of: photo.id).map { String($0+1) } ?? "")
                                        .font(.caption.bold()).foregroundStyle(.white).frame(width: 26, height: 26)
                                        .background(selection.contains(photo.id) ? theme.accent : Color.black.opacity(0.3), in: Circle())
                                        .overlay(Circle().stroke(.white, lineWidth: 2)).padding(6)
                                }
                        }.buttonStyle(.plain).accessibilityLabel(c("选择照片", "Select photo"))
                            .accessibilityValue(selection.firstIndex(of: photo.id).map { String($0+1) } ?? "0")
                            .accessibilityIdentifier("collage.photo."+photo.id)
                    }
                }
            }.padding(.vertical)
        }.background(AlbumBackground()).navigationTitle(title)
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button(c("继续", "Continue"), action: onConfirm).disabled(!limit.contains(selection.count) || loading || selection.contains(where: { id in !photos.contains { $0.id == id } }))
                    .accessibilityIdentifier("collage.photos.confirm")
            } }
            .task {
                loading = true
                if let groupID, library.groups.contains(where: { $0.id == groupID }) { photos = await library.service.photos(in: groupID) }
                else { photos = groupID == nil ? library.photos : []; missing = groupID != nil }
                // Preselection is never silently trimmed; inaccessible selections must be removed explicitly.
                loading = false
            }
            .safeAreaInset(edge: .bottom) {
                if selection.count > limit.upperBound || selection.contains(where: { id in !photos.contains { $0.id == id } }) {
                    HStack {
                        Text(c("请调整已选照片。", "Adjust the selection.")).font(.caption)
                        Button(c("清除选择", "Clear selection")) { selection = [] }
                    }.padding().background(theme.surface)
                }
            }
    }
}

struct CollageDraftsView: View {
    @EnvironmentObject private var workspace: CollageStore
    @EnvironmentObject private var store: DreamStore
    @Environment(\.albumTheme) private var theme
    @State private var editing: CollageDocument?
    @State private var renaming: CollageDocument?
    @State private var name = ""
    @State private var error: String?
    private func c(_ zh: String, _ en: String) -> String { AlbumCopy.pick(store.appLanguage, zh, en) }
    var body: some View {
        List {
            if workspace.documents.isEmpty { ContentUnavailableView(c("暂无拼图", "No collages"), systemImage: "square.grid.2x2", description: Text(c("进入分组，制作第一张拼图。", "Open an album to create your first collage."))) }
            ForEach(workspace.documents) { doc in
                Button { editing = doc } label: {
                    HStack(spacing: 14) {
                        DraftThumbnail(url: workspace.directory(doc.id).appendingPathComponent("preview.jpg"), date: doc.updatedAt)
                            .frame(width: 72, height: 72).clipped()
                        VStack(alignment: .leading, spacing: 5) {
                            Text(doc.name).font(.headline)
                            Text(doc.kind.title(store.appLanguage)).font(.caption)
                            Text(doc.updatedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(theme.secondary)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("collage.draft."+doc.id.uuidString)
                    .contextMenu {
                        Button(c("重命名", "Rename"), systemImage: "pencil") { name = doc.name; renaming = doc }
                        Button(c("复制", "Duplicate"), systemImage: "doc.on.doc") { perform { try workspace.duplicate(doc) } }
                        Button(c("删除草稿", "Delete draft"), systemImage: "trash", role: .destructive) { perform { try workspace.delete(doc) } }
                    }.listRowBackground(theme.surface)
            }
        }.scrollContentBackground(.hidden).background(AlbumBackground())
            .navigationTitle(c("我的拼图", "My collages")).navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .fullScreenCover(item: $editing) { doc in NavigationStack { CollageEditor(document: doc, workspace: workspace) } }
            .alert(c("重命名", "Rename"), isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField(c("名称", "Name"), text: $name)
                Button(c("保存", "Save")) { if var doc = renaming { doc.name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40)); perform { try workspace.save(doc) } }; renaming = nil }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button(c("取消", "Cancel"), role: .cancel) { renaming = nil }
            }
            .alert(c("操作失败", "Operation failed"), isPresented: Binding(get: { error != nil || workspace.error != nil }, set: { if !$0 { error = nil; workspace.error = nil } })) { Button(c("好", "OK")) { error = nil; workspace.error = nil } } message: { Text(error ?? workspace.error ?? "") }
    }
    private func perform(_ action: () throws -> Void) { do { try action() } catch { self.error = error.localizedDescription } }
}

private struct DraftThumbnail: View {
    let url: URL
    let date: Date
    @State private var image: UIImage?
    var body: some View {
        Group { if let image { Image(uiImage: image).resizable().scaledToFit() } else { Image(systemName: "square.grid.2x2") } }
            .task(id: date) { image = await Task.detached { try? CollageRenderer.load(url, maxPixel: 180) }.value }
    }
}
