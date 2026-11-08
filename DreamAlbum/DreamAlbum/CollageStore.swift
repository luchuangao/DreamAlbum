import SwiftUI
import ImageIO

@MainActor final class CollageStore: ObservableObject {
    @Published private(set) var documents: [CollageDocument] = []
    @Published var error: String?
    let root: URL
    init(root: URL? = nil) {
        let application = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var resolved = root ?? application.appendingPathComponent("CollageDrafts", isDirectory: true)
        #if DEBUG
        if root == nil && ProcessInfo.processInfo.arguments.contains("-dailyInboxFixture") {
            resolved = application.appendingPathComponent("CollageUITestDrafts", isDirectory: true)
            if ProcessInfo.processInfo.arguments.contains("-resetCollageFixture") { try? FileManager.default.removeItem(at: resolved) }
        }
        #endif
        self.root = resolved
        do {
            try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
            var value = URLResourceValues(); value.isExcludedFromBackup = true
            var directory = self.root; try directory.setResourceValues(value)
            refresh()
        } catch { self.error = error.localizedDescription }
    }
    func directory(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    func refresh() {
        do {
            let folders = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            var values: [CollageDocument] = []
            for folder in folders where UUID(uuidString: folder.lastPathComponent) != nil {
                do {
                    let d = try JSONDecoder().decode(CollageDocument.self, from: Data(contentsOf: folder.appendingPathComponent("document.json")))
                    guard d.schemaVersion == 1, d.id.uuidString == folder.lastPathComponent else { throw CollageError.invalidDocument }
                    values.append(d)
                } catch { self.error = error.localizedDescription }
            }
            documents = values.sorted { $0.updatedAt > $1.updatedAt }
        } catch { self.error = error.localizedDescription }
    }
    func save(_ document: CollageDocument) throws {
        var doc = document; doc.updatedAt = Date()
        let folder = directory(doc.id)
        guard FileManager.default.fileExists(atPath: folder.path) else { throw CollageError.missingImage }
        try JSONEncoder().encode(doc).write(to: folder.appendingPathComponent("document.json"), options: .atomic)
        if let i = documents.firstIndex(where: { $0.id == doc.id }) { documents[i] = doc }
        else { documents.append(doc) }
        documents.sort { $0.updatedAt > $1.updatedAt }
    }
    func duplicate(_ doc: CollageDocument) throws {
        var copy = doc; copy.id = UUID(); copy.name += " 2"; copy.updatedAt = Date()
        let target = directory(copy.id)
        do { try FileManager.default.copyItem(at: directory(doc.id), to: target); try save(copy) }
        catch { try? FileManager.default.removeItem(at: target); throw error }
    }
    func delete(_ doc: CollageDocument) throws {
        try FileManager.default.removeItem(at: directory(doc.id)); documents.removeAll { $0.id == doc.id }
    }
    func cleanup(_ doc: CollageDocument) {
        let folder = directory(doc.id).appendingPathComponent("assets")
        let active = Set(doc.layers.compactMap(\.file).map { URL(fileURLWithPath: $0).lastPathComponent })
        for url in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] where !active.contains(url.lastPathComponent) { try? FileManager.default.removeItem(at: url) }
    }
    func attach(_ urls: [URL], to id: UUID?, title: String, dreams: DreamStore) throws {
        guard !urls.isEmpty, id != nil || (!title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && dreams.canCreateDream) else { throw CollageError.invalidDocument }
        if let id, !dreams.activeDreams.contains(where: { $0.id == id }) { throw CollageError.invalidDocument }
        var paths: [String] = []
        do {
            for source in urls {
                guard CGImageSourceCreateWithURL(source as CFURL, nil) != nil else { throw CollageError.missingImage }
                // A copy, not ImageLibrary.saveImageData: exported resolution stays intact.
                let name = UUID().uuidString + "." + source.pathExtension
                let target = ImageLibrary.documentsDirectory.appendingPathComponent(name)
                paths.append(name); try FileManager.default.copyItem(at: source, to: target)
            }
            if let id, var dream = dreams.dreams.first(where: { $0.id == id }) {
                dream.imagePaths.removeAll { $0.hasPrefix("sample:") }
                dream.imagePaths += paths; dreams.update(dream)
            } else { dreams.addDream(title: String(title.prefix(12)), visionText: "", imagePaths: paths) }
        } catch {
            for path in paths { try? FileManager.default.removeItem(at: ImageLibrary.documentsDirectory.appendingPathComponent(path)) }
            throw error
        }
    }
}

/// Owns selected original bytes until the entire draft is committed. Retry skips saved inputs.
@MainActor final class CollageImportSession: ObservableObject {
    @Published var running = false
    @Published var progress = 0.0
    @Published var error: String?
    private var ready: [String: CollageLayer] = [:]
    private let staging: URL
    private var finalized = false
    private var closed = false
    private var task: Task<Void, Never>?
    init() {
        staging = FileManager.default.temporaryDirectory.appendingPathComponent("collage-input-"+UUID().uuidString)
    }
    func run(ids: [String], kind: CollageKind, groupID: String?, name: String, language: AppLanguage, service: any PhotoLibraryService, store: CollageStore, complete: @escaping (CollageDocument) -> Void) {
        guard !running, !closed, kind.limits.contains(ids.count), Set(ids).count == ids.count else { return }
        running = true; error = nil
        task = Task {
            defer { running = false }
            do {
                try FileManager.default.createDirectory(at: staging.appendingPathComponent("assets"), withIntermediateDirectories: true)
                for (index, id) in ids.enumerated() {
                    try Task.checkCancellation()
                    if let old = ready[id], let file = old.file, !FileManager.default.fileExists(atPath: staging.appendingPathComponent(file).path) { ready[id] = nil }
                    if ready[id] == nil {
                        let bytes = try await service.imageData(id: id) { [weak self] fraction in self?.progress = (Double(index)+fraction)/Double(ids.count) }
                        let folder = staging
                        let layer = try await Task.detached(priority: .utility) { try Self.writeAsset(bytes, into: folder) }.value
                        try Task.checkCancellation(); ready[id] = layer
                    }
                    progress = Double(index+1)/Double(ids.count)
                }
                try Task.checkCancellation()
                guard !closed else { throw CancellationError() }
                var doc = CollageDocument(name: name, kind: kind, sourceGroupID: groupID)
                doc.setKind(kind); doc.layers = ids.compactMap { ready[$0] }
                guard doc.isValidCount else { throw CollageError.invalidDocument }
                if kind == .comparison {
                    for i in doc.layers.indices { doc.layers[i].label = AlbumCopy.pick(language, i == 0 ? "之前" : "之后", i == 0 ? "Before" : "After") }
                }
                if kind == .poster { doc.title = AlbumCopy.pick(language, "我的梦想", "My dream"); doc.dateText = Date().formatted(date: .abbreviated, time: .omitted) }
                if kind == .freeform { doc.arrangeFreeLayers() }
                let target = store.directory(doc.id)
                do { try FileManager.default.moveItem(at: staging, to: target); try store.save(doc) }
                catch { try? FileManager.default.removeItem(at: target); throw error }
                finalized = true; complete(doc)
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
            if closed && !finalized { try? FileManager.default.removeItem(at: staging) }
        }
    }
    nonisolated static func writeAsset(_ bytes: Data, into directory: URL) throws -> CollageLayer {
        guard let source = CGImageSourceCreateWithData(bytes as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? NSNumber, let height = props[kCGImagePropertyPixelHeight] as? NSNumber,
              width.doubleValue > 0, height.doubleValue > 0 else { throw CollageError.missingImage }
        let orientation = (props[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let rotated = (5...8).contains(orientation)
        let file = "assets/"+UUID().uuidString+".image"
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("assets"), withIntermediateDirectories: true)
        try bytes.write(to: directory.appendingPathComponent(file), options: .atomic)
        return CollageLayer(file: file, pixelWidth: rotated ? height.doubleValue : width.doubleValue, pixelHeight: rotated ? width.doubleValue : height.doubleValue)
    }
    func close() {
        closed = true; task?.cancel()
        if !running && !finalized { try? FileManager.default.removeItem(at: staging) }
    }
}

@MainActor final class CollageEditorModel: ObservableObject {
    @Published var document: CollageDocument
    @Published var selection: UUID?
    @Published var preview: UIImage?
    @Published var error: String?
    @Published var page = 0
    @Published private(set) var undoItems: [CollageDocument] = []
    @Published private(set) var redoItems: [CollageDocument] = []
    private var baseline: CollageDocument?
    private var previewTask: Task<Void, Never>?
    private var version = 0
    private var thumbnailCache: [String: UIImage] = [:]
    let store: CollageStore
    init(document: CollageDocument, store: CollageStore) { self.document = document; self.store = store }
    var geometry: CollageGeometry { CollageGeometry.make(document) }
    var pages: [CGRect] { document.kind == .strip ? geometry.pages() : [CGRect(origin: .zero, size: geometry.size)] }
    var selected: CollageLayer? { document.layers.first { $0.id == selection } }
    func apply(_ edit: (inout CollageDocument) -> Void) {
        let before = document; edit(&document)
        guard before != document else { return }
        record(before); flush()
    }
    private func record(_ before: CollageDocument) {
        undoItems.append(before); if undoItems.count > 30 { undoItems.removeFirst() }; redoItems = []
    }
    func editLayer(_ edit: (inout CollageLayer) -> Void) {
        guard let id = selection, let i = document.layers.firstIndex(where: { $0.id == id }) else { return }
        apply { edit(&$0.layers[i]) }
    }
    func undo() { guard let d = undoItems.popLast() else { return }; redoItems.append(document); document = d; selection = nil; flush() }
    func redo() { guard let d = redoItems.popLast() else { return }; undoItems.append(document); document = d; selection = nil; flush() }
    func beginGesture() { if baseline == nil { baseline = document } }
    @discardableResult func swapPhotos(_ source: UUID, _ target: UUID) -> Bool {
        guard document.kind == .grid, source != target,
              let a = document.layers.firstIndex(where: { $0.id == source && $0.isPhoto && !$0.locked }),
              let b = document.layers.firstIndex(where: { $0.id == target && $0.isPhoto && !$0.locked }) else { return false }
        endGesture()
        apply { $0.layers.swapAt(a, b) }
        selection = source
        return true
    }
    func finishGridDrag(source: UUID, translation: CGSize, canvas: CGSize) {
        let layout = geometry
        if let original = layout.placements.first(where: { $0.id == source }), let baseline {
            let end = CGPoint(x: original.rect.midX + translation.width * layout.size.width / max(canvas.width, 1),
                              y: original.rect.midY + translation.height * layout.size.height / max(canvas.height, 1))
            if let target = layout.placements.first(where: { $0.id != source && $0.layer.isPhoto && !$0.layer.locked && $0.rect.contains(end) }) {
                document = baseline
                self.baseline = nil
                _ = swapPhotos(source, target.id)
                return
            }
        }
        endGesture()
    }
    func gesture(id: UUID, translation: CGSize, zoom: Double, angle: Double, canvasSize: CGSize) {
        guard let base = baseline, let i = document.layers.firstIndex(where: { $0.id == id }), let original = base.layers.first(where: { $0.id == id }), !original.locked else { return }
        selection = id
        if document.kind == .freeform || !original.isPhoto {
            var x = original.x + translation.width/max(1, canvasSize.width)
            var y = original.y + translation.height/max(1, canvasSize.height)
            let w = min(3, max(0.03, original.width*zoom)), h = min(3, max(0.03, original.height*zoom))
            if abs(x+w/2-0.5) < 0.015 { x = 0.5-w/2 }
            if abs(y+h/2-0.5) < 0.015 { y = 0.5-h/2 }
            document.layers[i].x = min(2, max(-1, x)); document.layers[i].y = min(2, max(-1, y))
            document.layers[i].width = w; document.layers[i].height = h
            document.layers[i].rotation = original.rotation+angle
        } else {
            document.layers[i].zoom = min(5, max(1, original.zoom*zoom))
            document.layers[i].offsetX = min(1, max(-1, original.offsetX+translation.width/max(1, canvasSize.width)*2))
            document.layers[i].offsetY = min(1, max(-1, original.offsetY+translation.height/max(1, canvasSize.height)*2))
        }
        schedulePreview(live: true)
    }
    func endGesture() { if let base = baseline, base != document { record(base) }; baseline = nil; flush() }
    func flush() {
        do { try store.save(document); error = nil } catch { self.error = error.localizedDescription }
        schedulePreview()
    }
    func schedulePreview(live: Bool = false) {
        // Keep rendering while fingers move. The final edit always requests its exact frame.
        if live, previewTask != nil { return }
        previewTask?.cancel(); version += 1
        let ticket = version, doc = document, folder = store.directory(document.id), pages = pages
        guard !pages.isEmpty else { error = CollageError.tooLong.localizedDescription; return }
        page = min(max(0, page), pages.count-1)
        let area = pages[page]
        previewTask = Task {
            defer { if ticket == version { previewTask = nil } }
            do {
                if !live { try await Task.sleep(for: .milliseconds(40)) }
                let cache = thumbnailCache
                let worker = Task.detached(priority: .userInitiated) {
                    var thumbnails = cache
                    var images: [UUID: UIImage] = [:]
                    for layer in doc.layers {
                        try Task.checkCancellation()
                        if let file = layer.file {
                            if thumbnails[file] == nil { thumbnails[file] = try CollageRenderer.load(CollageRenderer.assetURL(file, root: folder), maxPixel: 768) }
                            images[layer.id] = thumbnails[file]
                        }
                    }
                    let scale = doc.kind == .strip ? min(1, 480/min(area.width, area.height), 6000/max(area.width, area.height)) : min(1, 900/max(area.width, area.height))
                    let image = try CollageRenderer.render(doc, root: folder, geometry: CollageGeometry.make(doc), page: area, outputScale: scale, cached: images)
                    return (image, thumbnails)
                }
                let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                try Task.checkCancellation()
                guard ticket == version else { return }
                thumbnailCache = result.1
                let image = result.0
                preview = image
                if !live, let bytes = image.jpegData(compressionQuality: 0.75) { try? bytes.write(to: folder.appendingPathComponent("preview.jpg"), options: .atomic) }
            } catch is CancellationError { }
            catch { guard ticket == version else { return }; self.error = error.localizedDescription; preview = nil }
        }
    }
    func close() { endGesture(); previewTask?.cancel(); thumbnailCache = [:]; if error == nil { store.cleanup(document) } }
}
