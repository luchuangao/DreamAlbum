import SwiftUI
import Photos
import ImageIO

struct PhotoGroupsView: View {
    @Environment(\.albumTheme) private var theme
    @EnvironmentObject private var library: PhotoLibraryStore
    @EnvironmentObject private var store: DreamStore
    @State private var newGroup = false
    @State private var title = ""
    @State private var editing: LibraryGroup?
    @State private var infoGroup: LibraryGroup?
    @AppStorage("dream_album.hide_readonly_groups") private var hideReadOnlyGroups = false
    private var visibleGroups: [LibraryGroup] { library.groups.filter { !hideReadOnlyGroups || $0.isEditable } }
    private func c(_ zh: String, _ en: String) -> String { AlbumCopy.pick(store.appLanguage, zh, en) }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if library.hasAccess {
                    Text(c("\(visibleGroups.count) 个分组", "\(visibleGroups.count) albums"))
                        .font(.subheadline).foregroundStyle(.secondary).fixedSize()
                }
                Spacer()
                Menu {
                    Toggle(c("隐藏不可编辑分组", "Hide read-only albums"), isOn: $hideReadOnlyGroups)
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                        .foregroundStyle(hideReadOnlyGroups ? theme.accent : Color.secondary)
                        .frame(width: 40, height: 40).background(theme.surface, in: Circle())
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(c("筛选分组", "Filter albums"))
                    .accessibilityValue(hideReadOnlyGroups ? c("仅可编辑", "Editable only") : c("全部分组", "All albums"))
                    .accessibilityIdentifier("group.filters").disabled(!library.hasAccess)
                Button { title = ""; newGroup = true } label: {
                    Image(systemName: "plus").font(.title3.weight(.medium)).foregroundStyle(theme.background)
                        .frame(width: 40, height: 40).background(theme.accent, in: Circle())
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(c("新建分组", "New album"))
                    .disabled(!library.hasAccess || library.isChanging)
            }.frame(maxWidth: 700).padding(.horizontal, 16).padding(.top, 32).frame(maxWidth: .infinity)
            LimitedPhotosBanner()
            if !library.hasAccess { LibraryPermissionView() }
            else {
                List {
                    if visibleGroups.isEmpty { Text(hideReadOnlyGroups ? c("暂无可编辑分组", "No editable albums") : c("暂无分组", "No albums")) }
                    ForEach(visibleGroups) { group in
                        HStack(spacing: 8) {
                            NavigationLink {
                                PhotoBrowserView(group: group).libraryErrorAlert()
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: group.canAdd ? "folder" : "rectangle.stack").font(.title2).foregroundStyle(theme.accent).frame(width: 32)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(group.title).font(.headline)
                                        Text(c("\(group.count) 张", "\(group.count) photos")).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }.frame(minHeight: 94)
                            }
                            if group.canRename || group.canDelete {
                                Menu { groupActions(group) } label: {
                                    Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(Rectangle())
                                }.buttonStyle(.borderless)
                                    .accessibilityLabel(c("\(group.title)的操作", "Actions for \(group.title)"))
                                    .accessibilityIdentifier("group.actions." + group.id)
                            } else {
                                Button { infoGroup = group } label: {
                                    Text(group.isSystem ? c("系统", "System") : c("只读", "Read only"))
                                        .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8).padding(.vertical, 5)
                                        .background(.white.opacity(0.06), in: Capsule()).frame(minHeight: 44)
                                }.buttonStyle(.borderless).accessibilityIdentifier("group.info." + group.id)
                                    .accessibilityLabel(c("\(group.title)的说明", "About \(group.title)"))
                            }
                        }
                        .contextMenu { groupActions(group) }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if group.canDelete { Button(c("仅删分组", "Album only"), role: .destructive) { delete(group) } }
                            if group.canRename { Button(c("重命名", "Rename")) { title = group.title; editing = group }.tint(theme.accent) }
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 12))
                        .listRowSeparator(.hidden)
                        .listRowBackground(groupBackground(group))
                        .overlay(alignment: .bottom) { if group.id != visibleGroups.last?.id { Divider().padding(.leading, 62) } }
                        .disabled(library.isChanging)
                    }
                    if library.authorization == .limited {
                        Button(c("完整访问可查看其他相册", "Full access shows other albums")) { openPhotoSettings() }
                    }
                }.listStyle(.plain).scrollContentBackground(.hidden)
                    .contentMargins(.top, 28, for: .scrollContent)
                    .frame(maxWidth: 700).padding(.horizontal, 16).frame(maxWidth: .infinity)
            }
        }
        .background(AlbumBackground()).navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .task { await library.activate() }
        .alert(c("新建分组", "New album"), isPresented: $newGroup) {
            TextField(c("分组名称", "Album name"), text: $title)
            Button(c("取消", "Cancel"), role: .cancel) { }
            Button(c("创建", "Create")) {
                let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                Task { await library.perform { try await library.service.createGroup(title: name, photoIDs: []) } }
            }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert(c("重命名分组", "Rename album"), isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            TextField(c("分组名称", "Album name"), text: $title)
            Button(c("取消", "Cancel"), role: .cancel) { editing = nil }
            Button(c("保存", "Save")) {
                guard let id = editing?.id else { return }
                let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
                editing = nil
                guard !name.isEmpty else { return }
                Task { await library.perform { try await library.service.renameGroup(id: id, title: name) } }
            }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert(infoGroup?.isSystem == true ? c("系统相册", "System album") : c("只读相册", "Read-only album"), isPresented: Binding(get: { infoGroup != nil }, set: { if !$0 { infoGroup = nil } })) {
            Button(c("好", "OK")) { infoGroup = nil }
        } message: {
            Text(infoGroup?.isSystem == true
                 ? c("可整理其中的照片。相册名称和分类由系统管理。", "You can organize the photos inside. The system manages the album name and category.")
                 : c("可整理其中的照片，此相册暂不支持修改。", "You can organize the photos inside. This album cannot be edited."))
        }
        .libraryErrorAlert()
    }
    private func groupBackground(_ group: LibraryGroup) -> some View {
        let first = group.id == visibleGroups.first?.id
        let last = group.id == visibleGroups.last?.id
        return UnevenRoundedRectangle(topLeadingRadius: first ? 14 : 0,
                                      bottomLeadingRadius: last ? 14 : 0,
                                      bottomTrailingRadius: last ? 14 : 0,
                                      topTrailingRadius: first ? 14 : 0)
            .fill(theme.surface)
    }
    @ViewBuilder
    private func groupActions(_ group: LibraryGroup) -> some View {
        if group.canRename { Button(c("重命名", "Rename"), systemImage: "pencil") { title = group.title; editing = group } }
        if group.canDelete {
            Button(c("删除分组（保留照片）", "Delete album (keep photos)"), systemImage: "folder.badge.minus", role: .destructive) { delete(group) }
            Button(c("删除分组及 \(group.count) 张原图", "Delete album and \(group.count) originals"), systemImage: "trash", role: .destructive) {
                Task { await library.deleteGroupAndPhotos(group.id) }
            }
        }
    }
    private func delete(_ group: LibraryGroup) {
        Task { await library.perform { try await library.service.deleteGroup(id: group.id) } }
    }
}

struct GroupDestinationView: View {
    @Environment(\.albumTheme) private var theme
    @EnvironmentObject private var library: PhotoLibraryStore
    @EnvironmentObject private var store: DreamStore
    @Environment(\.dismiss) private var dismiss
    let ids: [String]
    @State private var name = ""
    @FocusState private var editingName: Bool
    private func c(_ zh: String, _ en: String) -> String { AlbumCopy.pick(store.appLanguage, zh, en) }
    var body: some View {
        Form {
            Section(c("新建分组", "New album")) {
                TextField(c("分组名称", "Album name"), text: $name)
                    .focused($editingName).submitLabel(.done).onSubmit { editingName = false }
                Button(c("创建并加入 \(ids.count) 张照片", "Create and add \(ids.count) photos")) {
                    let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    Task { if await library.perform({ try await library.service.createGroup(title: title, photoIDs: ids) }) { dismiss() } }
                }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Section(c("加入已有分组", "Add to existing album")) {
                ForEach(library.groups.filter(\.canAdd)) { group in
                    Button {
                        Task { if await library.perform({ try await library.service.addPhotos(ids, to: group.id) }) { dismiss() } }
                    } label: { HStack { Text(group.title).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading); Text("\(group.count)").foregroundStyle(.secondary).fixedSize() } }
                        .accessibilityIdentifier("group.destination." + group.id)
                }
                if library.authorization == .limited {
                    Button(c("查看其他相册需要完整访问", "Full access is needed for other albums")) { openPhotoSettings() }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .disabled(library.isChanging)
        .overlay { if library.isChanging { ProgressView().padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
        .scrollContentBackground(.hidden)
            .background(AlbumBackground())
            .navigationTitle(c("加入分组", "Add to album")).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(c("取消", "Cancel")) { dismiss() }.disabled(library.isChanging) }
            ToolbarItem(placement: .keyboard) { Button(c("完成", "Done")) { editingName = false } }
        }
        .interactiveDismissDisabled(library.isChanging)
        .libraryErrorAlert().preferredColorScheme(.light)
    }
}

struct DreamImportView: View {
    @Environment(\.albumTheme) private var theme
    @EnvironmentObject private var library: PhotoLibraryStore
    @EnvironmentObject private var store: DreamStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var importer = DreamPhotoImport()
    let ids: [String]
    @State private var title = ""
    @State private var targetID: UUID?
    @State private var began = false
    @State private var commitFailed = false
    private func c(_ zh: String, _ en: String) -> String { AlbumCopy.pick(store.appLanguage, zh, en) }
    var body: some View {
        Form {
            Section {
                Text(c("将保存独立图片副本。之后清理手机原图不会影响梦想画册。", "Independent image copies will be saved. Cleaning up originals later will not affect your dream album."))
                    .font(.subheadline).foregroundStyle(.secondary)
                Picker(c("目标画册", "Destination"), selection: $targetID) {
                    Text(c("新建梦想画册", "New dream album")).tag(Optional<UUID>.none)
                    ForEach(store.activeDreams) { dream in Text(dream.title).tag(Optional(dream.id)) }
                }.disabled(began)
                if targetID == nil {
                    TextField(c("画册名称（最多12字）", "Album name (up to 12 characters)"), text: $title)
                        .onChange(of: title) { _, value in title = String(value.prefix(12)) }.disabled(began)
                }
            }
            Section {
                if !began {
                    Text(c("已选择 \(ids.count) 张照片", "\(ids.count) photos selected"))
                    Button(c("保存图片副本", "Save image copies")) { began = true; importer.run(ids: ids, service: library.service) }
                        .disabled(ids.isEmpty || (targetID == nil && (title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.canCreateDream)))
                } else {
                    if importer.isRunning {
                        ProgressView(value: importer.progress)
                        Text(c("正在下载并保存图片…", "Downloading and saving images…")).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(c("已保存 \(importer.ready.count) / \(ids.count) 张", "Saved \(importer.ready.count) / \(ids.count)"))
                    if !importer.failed.isEmpty {
                        Text(importer.error ?? c("部分图片保存失败", "Some images could not be saved")).font(.caption).foregroundStyle(theme.destructive)
                        Button(c("重试失败的 \(importer.failed.count) 张", "Retry \(importer.failed.count) failed photos")) { importer.run(ids: importer.failed, service: library.service) }.disabled(importer.isRunning)
                    }
                    Button(c("加入梦想画册", "Add to dream album")) {
                        if importer.commit(to: targetID, title: title.trimmingCharacters(in: .whitespacesAndNewlines), store: store) { dismiss() }
                        else { commitFailed = true }
                    }.disabled(importer.isRunning || importer.ready.isEmpty)
                }
            }
        }
        .scrollContentBackground(.hidden)
            .background(AlbumBackground())
            .navigationTitle(c("加入梦想画册", "Add to dream album")).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(c("取消", "Cancel")) { importer.close(); dismiss() } } }
        .onDisappear { importer.close() }
        .alert(c("画册已不可用", "Album unavailable"), isPresented: $commitFailed) {
            Button(c("好", "OK")) { }
        } message: { Text(c("请重新选择画册。", "Choose another album.")) }
        .preferredColorScheme(.light)
    }
}

private struct DreamCoverImage: View {
    @Environment(\.albumTheme) private var theme
    @Environment(\.libraryScreenActive) private var screenActive
    let path: String?
    @State private var image: UIImage?
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                theme.surface
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                } else { Image(systemName: "photo").foregroundStyle(.secondary) }
            }
        }
        .task(id: "\(path ?? "")-\(screenActive)") {
            image = nil
            guard screenActive else { return }
            let loaded = await Task.detached(priority: .utility) { () -> UIImage? in
                guard let path else { return nil }
                if path.hasPrefix("sample:") { return UIImage(named: "DemoDream") }
                guard let url = ImageLibrary.imageURL(for: path),
                      let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                      let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 1200
                      ] as CFDictionary) else { return nil }
                return UIImage(cgImage: thumbnail)
            }.value
            if !Task.isCancelled { image = loaded }
        }
        .onDisappear { image = nil }
    }
}

struct DreamGalleryView: View {
    @Environment(\.albumTheme) private var theme
    @EnvironmentObject private var store: DreamStore
    @State private var newDream = false
    @State private var rename: Dream?
    @State private var title = ""
    @State private var draggedID: UUID?
    private func c(_ zh: String, _ en: String) -> String { AlbumCopy.pick(store.appLanguage, zh, en) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                HStack {
                    Text(c("\(store.activeDreams.count) 本画册", "\(store.activeDreams.count) albums"))
                        .font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Button { newDream = true } label: {
                        Image(systemName: "plus").font(.title3.weight(.medium)).foregroundStyle(theme.background)
                            .frame(width: 40, height: 40).background(theme.accent, in: Circle())
                    }.buttonStyle(.plain).accessibilityLabel(c("新建梦想画册", "New dream album"))
                }
                if store.activeDreams.isEmpty {
                    ContentUnavailableView(c("暂无画册", "No dream albums"), systemImage: "book", description: Text(c("添加照片，创建画册。", "Add photos to create an album.")))
                }
                LazyVStack(spacing: 20) {
                    ForEach(store.activeDreams) { dream in
                        NavigationLink(value: dream.id) { cover(dream) }.buttonStyle(.plain)
                            .contextMenu {
                                Button(c("重命名", "Rename"), systemImage: "pencil") { title = dream.title; rename = dream }
                                Button(c("归档", "Archive"), systemImage: "archivebox") { store.archive(dream) }
                                Button(c("删除画册", "Delete dream album"), systemImage: "trash", role: .destructive) { store.delete(dream) }
                            }
                            .onDrag { draggedID = dream.id; return NSItemProvider(object: dream.id.uuidString as NSString) }
                            .onDrop(of: [.text], isTargeted: nil) { providers in
                                guard let draggedID, providers.count > 0 else { return false }
                                store.moveDream(draggedID, before: dream.id); self.draggedID = nil; return true
                            }
                    }
                }
            }
            .frame(maxWidth: 700)
            .padding(.horizontal, 20).padding(.top, 32).padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .background(AlbumBackground()).navigationTitle("")
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: UUID.self) { id in
            if let dream = store.dreams.first(where: { $0.id == id }) { DreamDetailView(dream: dream).toolbar(.visible, for: .navigationBar) }
        }
        .sheet(isPresented: $newDream) { NewDreamSheet() }
        .alert(c("重命名画册", "Rename dream album"), isPresented: Binding(get: { rename != nil }, set: { if !$0 { rename = nil } })) {
            TextField(c("画册名称", "Album name"), text: $title)
            Button(c("取消", "Cancel"), role: .cancel) { rename = nil }
            Button(c("保存", "Save")) {
                if let id = rename?.id, var latest = store.dreams.first(where: { $0.id == id }) {
                    latest.title = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(12)); store.update(latest)
                }
                rename = nil
            }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }

    }
    private func cover(_ dream: Dream) -> some View {
        ZStack(alignment: .bottomLeading) {
            DreamCoverImage(path: dream.imagePaths.first).allowsHitTesting(false).accessibilityHidden(true)
            LinearGradient(colors: [.clear, .black.opacity(0.88)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 8) {
                Text(dream.title).font(.title2.bold()).foregroundStyle(.white).lineLimit(2)
                HStack {
                    Text(dream.imagePaths.first?.hasPrefix("sample:") == true ? c("内置示例画面", "Built-in sample") : c("已保存独立副本 · \(dream.imagePaths.count) 张照片", "Independent copies · \(dream.imagePaths.count) photos")).font(.caption).foregroundStyle(.white.opacity(0.76))
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.white.opacity(0.8))
                }
            }.padding(20)
        }
        .frame(maxWidth: .infinity).frame(height: 350)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(dream.title + "，" + (dream.imagePaths.first?.hasPrefix("sample:") == true
            ? c("内置示例画面", "Built-in sample")
            : c("已保存独立副本 · \(dream.imagePaths.count) 张照片", "Independent copies · \(dream.imagePaths.count) photos")))
    }
}
