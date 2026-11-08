import XCTest
import UIKit
import ImageIO
import Photos
import UniformTypeIdentifiers
import Darwin
@testable import DreamAlbum

#if targetEnvironment(simulator)
/// Opt-in because the success case creates assets in the simulator's Photos library.
@MainActor final class CollagePhotoKitAcceptanceTests: XCTestCase {
    private func requireDisposableSimulator() throws {
        let device = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? ""
        try XCTSkipUnless(device.hasPrefix("DreamAlbum Collage QA "), "Requires a disposable DreamAlbum Collage QA simulator.")
    }

    func testSaveExportedJPEGAndPNGWithOriginalDimensions() async throws {
        try requireDisposableSimulator()
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized else { return XCTFail("Grant full Photos access on the disposable simulator before readback.") }
        let folder = try testCollageRoot()
        defer { try? FileManager.default.removeItem(at: folder) }
        var doc = CollageDocument(name: "PhotoKit", kind: .grid)
        doc.ratio = .portrait
        doc.layers = [try testPhoto(folder), try testPhoto(folder, color: .blue)]
        let jpeg = try await CollageRenderer.export(doc, root: folder, longEdge: 2048, fileFormat: .jpeg) { _ in }
        defer { CollageRenderer.cleanExport(jpeg) }
        let png = try await CollageRenderer.export(doc, root: folder, longEdge: 4096, fileFormat: .png) { _ in }
        defer { CollageRenderer.cleanExport(png) }
        let inputs = [try XCTUnwrap(jpeg.first), try XCTUnwrap(png.first)]
        let service = SystemPhotoLibraryService()
        func assetIDs() -> Set<String> {
            let assets = PHAsset.fetchAssets(with: .image, options: nil)
            var ids: Set<String> = []
            assets.enumerateObjects { asset, _, _ in ids.insert(asset.localIdentifier) }
            return ids
        }
        let before = assetIDs()
        do {
            try await service.saveGeneratedImages([inputs[0], folder.appendingPathComponent("missing.png")])
            XCTFail("A partly unreadable batch must fail.")
        } catch PhotoLibraryFailure.imageUnavailable { }
        XCTAssertEqual(assetIDs(), before)
        try await service.saveGeneratedImages(inputs)
        let added = assetIDs().subtracting(before)
        XCTAssertEqual(added.count, 2)
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: Array(added), options: nil)
        var dimensions: [String: CGSize] = [:]
        assets.enumerateObjects { asset, _, _ in
            if let resource = PHAssetResource.assetResources(for: asset).first(where: { $0.type == .photo }) {
                dimensions[resource.uniformTypeIdentifier] = CGSize(width: asset.pixelWidth, height: asset.pixelHeight)
            }
        }
        XCTAssertEqual(dimensions[UTType.jpeg.identifier], CGSize(width: 1536, height: 2048))
        XCTAssertEqual(dimensions[UTType.png.identifier], CGSize(width: 3072, height: 4096))
    }

    func testDeniedAddAccessKeepsGeneratedFile() async throws {
        try requireDisposableSimulator()
        XCTAssertEqual(PHPhotoLibrary.authorizationStatus(for: .addOnly), .denied)
        let folder = try testCollageRoot()
        defer { try? FileManager.default.removeItem(at: folder) }
        var doc = CollageDocument(name: "PhotoKit", kind: .grid)
        doc.layers = [try testPhoto(folder), try testPhoto(folder)]
        let files = try await CollageRenderer.export(doc, root: folder, longEdge: 2048, fileFormat: .jpeg) { _ in }
        defer { CollageRenderer.cleanExport(files) }
        do {
            try await SystemPhotoLibraryService().saveGeneratedImages(files)
            XCTFail("Denied Photos access must not report a successful save.")
        } catch PhotoLibraryFailure.saveDenied { }
        XCTAssertEqual(try imageDimensions(XCTUnwrap(files.first)), CGSize(width: 2048, height: 2048))
    }
}
#endif

private func testCollageRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("collage-test-"+UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
private func testPhoto(_ folder: URL, size: CGSize = CGSize(width: 80, height: 60), color: UIColor = .red, orientation: Int = 1) throws -> CollageLayer {
    let format = UIGraphicsImageRendererFormat(); format.scale = 1
    let image = UIGraphicsImageRenderer(size: size, format: format).image { context in color.setFill(); context.fill(CGRect(origin: .zero, size: size)) }
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image.cgImage!, [kCGImagePropertyOrientation: orientation, kCGImageDestinationLossyCompressionQuality: 1] as CFDictionary)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    return try CollageImportSession.writeAsset(data as Data, into: folder)
}
private func imageDimensions(_ url: URL) throws -> CGSize {
    let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
    let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    return CGSize(width: (props[kCGImagePropertyPixelWidth] as! NSNumber).doubleValue, height: (props[kCGImagePropertyPixelHeight] as! NSNumber).doubleValue)
}
private func centerColor(_ image: UIImage) -> (UInt8, UInt8, UInt8) {
    var pixels = [UInt8](repeating: 0, count: 4)
    pixels.withUnsafeMutableBytes { bytes in
        let ctx = CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image.cgImage!, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    }
    return (pixels[0], pixels[1], pixels[2])
}
private func collageFootprint() -> UInt64 {
    var value = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let capacity = Int(count)
    let result = withUnsafeMutablePointer(to: &value) { pointer in pointer.withMemoryRebound(to: integer_t.self, capacity: capacity) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) } }
    return result == KERN_SUCCESS ? value.phys_footprint : 0
}

final class CollageGeometryTests: XCTestCase {
    func testFiveKindsCountBoundariesAndRoundTripPreserveEditing() throws {
        for kind in CollageKind.allCases {
            var doc = CollageDocument(name: "拼图", kind: kind, sourceGroupID: "local-only")
            doc.layers = (0..<kind.limits.lowerBound).map { i in CollageLayer(file: "assets/\(i).image", pixelWidth: 600, pixelHeight: 800, rotation: 12, zoom: 2, locked: true) }
            doc.layers.append(CollageLayer(text: "目标与成长", x: 0.2, y: 0.4, width: 0.6, height: 0.2))
            XCTAssertTrue(doc.isValidCount)
            XCTAssertEqual(try JSONDecoder().decode(CollageDocument.self, from: JSONEncoder().encode(doc)), doc)
            doc.layers = []; XCTAssertFalse(doc.isValidCount)
            doc.layers = (0...kind.limits.upperBound).map { CollageLayer(file: "assets/\($0).image") }; XCTAssertFalse(doc.isValidCount)
        }
    }
    func testGridComparisonPosterTemplatesHaveBoundedDistinctRects() {
        for kind in [CollageKind.grid, .comparison, .poster] {
            for layout in 0..<3 {
                for count in kind.limits {
                    var doc = CollageDocument(name: "", kind: kind); doc.setKind(kind); doc.layout = layout
                    doc.layers = (0..<count).map { CollageLayer(file: "assets/\($0).image") }
                    let geo = CollageGeometry.make(doc)
                    XCTAssertEqual(geo.placements.count, count)
                    for p in geo.placements {
                        XCTAssertGreaterThan(p.rect.width, 0); XCTAssertGreaterThan(p.rect.height, 0)
                        XCTAssertTrue(CGRect(origin: .zero, size: geo.size).contains(p.rect))
                    }
                    if kind == .poster { XCTAssertNotNil(geo.header) }
                }
            }
        }
    }
    func testRatiosAndFreeTransformsSurviveTemplateChanges() {
        var doc = CollageDocument(name: "", kind: .freeform)
        doc.layers = [CollageLayer(file: "assets/a", x: 0.2, y: 0.3, width: 0.4, height: 0.5, rotation: 32)]
        doc.hasFreeLayout = true
        for ratio in CollageRatio.allCases {
            doc.ratio = ratio
            let g = CollageGeometry.make(doc)
            XCTAssertEqual(g.size.width/g.size.height, ratio.value, accuracy: 0.001)
            XCTAssertEqual(g.placements[0].rect.minX/g.size.width, 0.2, accuracy: 0.001)
        }
        doc.setKind(.poster); doc.setKind(.freeform)
        XCTAssertEqual(doc.layers[0].rotation, 32); XCTAssertTrue(doc.hasFreeLayout)
        doc.setKind(.strip)
        XCTAssertEqual(doc.layers[0].rotation, 0)
    }
    func testManualCropChangesStripLengthAndPagingDoesNotDropPixels() {
        var doc = CollageDocument(name: "", kind: .strip)
        doc.margin = 0; doc.spacing = 0
        doc.layers = [CollageLayer(file: "assets/a", pixelWidth: 144, pixelHeight: 1600), CollageLayer(file: "assets/b", pixelWidth: 144, pixelHeight: 1600)]
        let g = CollageGeometry.make(doc)
        XCTAssertEqual(g.size, CGSize(width: 1440, height: 32000))
        XCTAssertEqual(g.pages().map(\.height), [16000, 16000])
        doc.layers[0].cropTop = 0.25
        XCTAssertEqual(CollageGeometry.make(doc).size.height, 28000, accuracy: 0.01)
        doc.horizontal = true
        let horizontal = CollageGeometry.make(doc)
        XCTAssertEqual(horizontal.size.height, 1440)
        XCTAssertGreaterThan(horizontal.size.width, 0)
    }
}

final class CollageRenderingTests: XCTestCase {
    func testOrientationMetadataAndDecodeAreUpright() throws {
        let root = try testCollageRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let layer = try testPhoto(root, size: CGSize(width: 40, height: 80), orientation: 6)
        XCTAssertEqual(layer.pixelWidth, 80); XCTAssertEqual(layer.pixelHeight, 40)
        let image = try CollageRenderer.load(root.appendingPathComponent(layer.file!), maxPixel: 200)
        XCTAssertEqual(image.size, CGSize(width: 80, height: 40))
    }
    func testBothFormatsAndOutputSizesForAllFiveKinds() async throws {
        let root = try testCollageRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let red = try testPhoto(root), blue = try testPhoto(root, size: CGSize(width: 60, height: 90), color: .blue)
        for kind in CollageKind.allCases {
            var doc = CollageDocument(name: "测试", kind: kind); doc.setKind(kind); doc.layers = [red, blue]
            if kind == .freeform { doc.arrangeFreeLayers() }
            doc.title = "梦想"; doc.subtitle = "成长记录"; doc.dateText = "2026"
            for format in CollageFileFormat.allCases {
                let urls = try await CollageRenderer.export(doc, root: root, longEdge: 2048, fileFormat: format) { _ in }
                defer { CollageRenderer.cleanExport(urls) }
                XCTAssertFalse(urls.isEmpty)
                let size = try imageDimensions(urls[0])
                if kind == .strip { XCTAssertEqual(size.width, 1440) } else { XCTAssertEqual(max(size.width, size.height), 2048) }
                let image = try CollageRenderer.load(urls[0], maxPixel: 100)
                XCTAssertGreaterThan(image.size.width, 0)
            }
        }
        var high = CollageDocument(name: "High", kind: .grid); high.layers = [red, blue]
        let urls = try await CollageRenderer.export(high, root: root, longEdge: 4096, fileFormat: .jpeg) { _ in }
        defer { CollageRenderer.cleanExport(urls) }
        let size = try imageDimensions(urls[0]); XCTAssertEqual(max(size.width, size.height), 4096)
    }
    func testLongPageBoundaryColorsAndExactResolution() async throws {
        let root = try testCollageRoot(); defer { try? FileManager.default.removeItem(at: root) }
        var doc = CollageDocument(name: "Long", kind: .strip); doc.margin = 0; doc.spacing = 0
        doc.layers = [try testPhoto(root, size: CGSize(width: 144, height: 1600), color: .red), try testPhoto(root, size: CGSize(width: 144, height: 1600), color: .blue)]
        let urls = try await CollageRenderer.export(doc, root: root, longEdge: 2048, fileFormat: .png) { _ in }
        defer { CollageRenderer.cleanExport(urls) }
        XCTAssertEqual(urls.count, 2)
        for url in urls { XCTAssertEqual(try imageDimensions(url), CGSize(width: 1440, height: 16000)) }
        let a = centerColor(try CollageRenderer.load(urls[0], maxPixel: 30)), b = centerColor(try CollageRenderer.load(urls[1], maxPixel: 30))
        XCTAssertGreaterThan(a.0, 200); XCTAssertLessThan(a.2, 30)
        XCTAssertGreaterThan(b.2, 200); XCTAssertLessThan(b.0, 30)
    }
    func testMissingCorruptAndEscapingSourcesFailInsteadOfBlankExport() async throws {
        let root = try testCollageRoot(); defer { try? FileManager.default.removeItem(at: root) }
        var doc = CollageDocument(name: "", kind: .grid)
        let good = try testPhoto(root)
        for bad in ["assets/missing.image", "assets/../../escape.image"] {
            doc.layers = [good, CollageLayer(file: bad)]
            do { _ = try await CollageRenderer.export(doc, root: root, longEdge: 2048, fileFormat: .jpeg) { _ in }; XCTFail("Must fail") } catch { }
        }
        XCTAssertThrowsError(try CollageImportSession.writeAsset(Data([1, 2, 3]), into: root))
    }
    func testCancellationRemovesTemporaryExportFiles() async throws {
        let root = try testCollageRoot(); defer { try? FileManager.default.removeItem(at: root) }
        var doc = CollageDocument(name: "", kind: .grid); let p = try testPhoto(root); doc.layers = [p, p]
        let temp = FileManager.default.temporaryDirectory
        let before = Set(try FileManager.default.contentsOfDirectory(atPath: temp.path).filter { $0.hasPrefix("collage-export-") })
        let task = Task { try await CollageRenderer.export(doc, root: root, longEdge: 4096, fileFormat: .png) { _ in } }
        task.cancel()
        do { let files = try await task.value; CollageRenderer.cleanExport(files); XCTFail("Cancellation must propagate") } catch is CancellationError { }
        let after = Set(try FileManager.default.contentsOfDirectory(atPath: temp.path).filter { $0.hasPrefix("collage-export-") })
        XCTAssertEqual(before, after)
    }
    func testTwentyLargeSourcesPagedExportMemory() async throws {
        let root = try testCollageRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let first: CollageLayer = try autoreleasepool { try testPhoto(root, size: CGSize(width: 4000, height: 3000), color: .systemBlue) }
        var doc = CollageDocument(name: "20 large photos", kind: .strip)
        for i in 0..<20 {
            var p = first; p.id = UUID(); p.file = "assets/large-\(i).image"
            try FileManager.default.copyItem(at: root.appendingPathComponent(first.file!), to: root.appendingPathComponent(p.file!)); doc.layers.append(p)
        }
        let baseline = collageFootprint()
        let watcher = Task.detached { var peak = baseline; while !Task.isCancelled { peak = max(peak, collageFootprint()); try? await Task.sleep(for: .milliseconds(20)) }; return peak }
        defer { watcher.cancel() }
        let urls = try await CollageRenderer.export(doc, root: root, longEdge: 2048, fileFormat: .jpeg) { _ in }
        defer { CollageRenderer.cleanExport(urls) }
        watcher.cancel(); let peak = await watcher.value
        XCTAssertEqual(urls.count, CollageGeometry.make(doc).pages().count)
        XCTAssertLessThan(peak > baseline ? peak-baseline : 0, 512*1024*1024)
        let report = "sources=20; each=4000x3000; pages=\(urls.count); baseline=\(baseline); peak=\(peak); delta=\(peak > baseline ? peak-baseline : 0)"
        let attachment = XCTAttachment(string: report); attachment.name = "collage-memory"; attachment.lifetime = .keepAlways; add(attachment)
        print(report)
    }
}

@MainActor final class CollagePersistenceTests: XCTestCase {
    func testGridReorderIsUndoableAndRespectsLockedLayers() throws {
        let root = try testCollageRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let workspace = CollageStore(root: root)
        var doc = CollageDocument(name: "Grid", kind: .grid)
        doc.layers = [try testPhoto(workspace.directory(doc.id)), try testPhoto(workspace.directory(doc.id), color: .blue)]
        try workspace.save(doc)
        let model = CollageEditorModel(document: doc, store: workspace)
        XCTAssertTrue(model.swapPhotos(doc.layers[0].id, doc.layers[1].id))
        XCTAssertEqual(model.document.layers.map(\.id), doc.layers.reversed().map(\.id))
        XCTAssertEqual(model.undoItems.count, 1)
        model.undo(); XCTAssertEqual(model.document.layers, doc.layers)
        model.redo(); XCTAssertNotEqual(model.document.layers, doc.layers)
        model.apply { $0.layers[0].locked = true }
        let before = model.document
        XCTAssertFalse(model.swapPhotos(doc.layers[0].id, doc.layers[1].id))
        XCTAssertEqual(model.document, before)
        model.close()
    }
    func testDraftDuplicateDeleteDoesNotChangeOriginalOrExports() throws {
        let root = try testCollageRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let workspace = CollageStore(root: root.appendingPathComponent("drafts"))
        var doc = CollageDocument(name: "草稿", kind: .freeform)
        doc.layers = [try testPhoto(workspace.directory(doc.id))]; doc.arrangeFreeLayers(); try workspace.save(doc)
        try workspace.duplicate(doc)
        XCTAssertEqual(workspace.documents.count, 2)
        let copy = try XCTUnwrap(workspace.documents.first { $0.id != doc.id })
        let originalFile = workspace.directory(doc.id).appendingPathComponent(doc.layers[0].file!)
        let copyFile = workspace.directory(copy.id).appendingPathComponent(copy.layers[0].file!)
        XCTAssertNotEqual(originalFile, copyFile)
        try workspace.delete(doc)
        XCTAssertTrue(FileManager.default.fileExists(atPath: copyFile.path))
        let reopened = CollageStore(root: workspace.root)
        XCTAssertEqual(reopened.documents.count, 1); XCTAssertEqual(reopened.documents[0].layers, copy.layers)
    }
    func testUndoLimitGestureCoalescingLockAndAutosave() throws {
        let root = try testCollageRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let workspace = CollageStore(root: root.appendingPathComponent("drafts"))
        var doc = CollageDocument(name: "Undo", kind: .freeform)
        doc.layers = [try testPhoto(workspace.directory(doc.id))]; try workspace.save(doc)
        let model = CollageEditorModel(document: doc, store: workspace)
        for i in 0..<35 { model.apply { $0.subtitle = "\(i)" } }
        XCTAssertEqual(model.undoItems.count, 30)
        let before = model.undoItems.count
        model.beginGesture()
        model.gesture(id: doc.layers[0].id, translation: CGSize(width: 10, height: 20), zoom: 1, angle: 4, canvasSize: CGSize(width: 300, height: 300))
        model.gesture(id: doc.layers[0].id, translation: CGSize(width: 30, height: 40), zoom: 1.2, angle: 8, canvasSize: CGSize(width: 300, height: 300))
        model.endGesture(); XCTAssertEqual(model.undoItems.count, before)
        let moved = model.document
        model.undo(); XCTAssertNotEqual(model.document.layers[0].x, moved.layers[0].x)
        model.redo(); XCTAssertEqual(model.document.layers, moved.layers)
        model.apply { $0.layers[0].locked = true }
        let locked = model.document
        model.beginGesture(); model.gesture(id: locked.layers[0].id, translation: CGSize(width: 99, height: 99), zoom: 2, angle: 90, canvasSize: CGSize(width: 300, height: 300)); model.endGesture()
        XCTAssertEqual(model.document.layers, locked.layers)
        XCTAssertEqual(CollageStore(root: workspace.root).documents[0].layers, locked.layers)
        model.close()
    }
    func testImportRetrySkipsCompletedCopiesAndSurvivesOriginalDeletion() async throws {
        let root = try testCollageRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let workspace = CollageStore(root: root)
        let service = FakePhotoLibrary(); service.failedImages = ["b"]
        let importer = CollageImportSession(); var result: CollageDocument?
        importer.run(ids: ["a", "b"], kind: .grid, groupID: "g", name: "Retry", language: .chinese, service: service, store: workspace) { result = $0 }
        while importer.running { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNil(result); XCTAssertNotNil(importer.error)
        service.failedImages = []
        importer.run(ids: ["a", "b"], kind: .grid, groupID: "g", name: "Retry", language: .chinese, service: service, store: workspace) { result = $0 }
        while importer.running { try await Task.sleep(for: .milliseconds(10)) }
        let doc = try XCTUnwrap(result)
        XCTAssertEqual(service.dataRequests, 3)
        importer.close(); try await service.deletePhotos(["a", "b"])
        for p in doc.layers { XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.directory(doc.id).appendingPathComponent(p.file!).path)) }
    }
    func testExportAttachmentRetains4096AndDraftDeleteKeepsAlbumCopy() async throws {
        let root = try testCollageRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let workspace = CollageStore(root: root)
        var doc = CollageDocument(name: "Album", kind: .poster)
        doc.layers = [try testPhoto(workspace.directory(doc.id))]; try workspace.save(doc)
        let urls = try await CollageRenderer.export(doc, root: workspace.directory(doc.id), longEdge: 4096, fileFormat: .jpeg) { _ in }
        defer { CollageRenderer.cleanExport(urls) }
        let dreams = DreamStore(); let old = dreams.dreams
        defer { dreams.dreams = old }
        let target = Dream(title: "成图", visionText: "", imagePaths: ["sample:marathon"]); dreams.dreams = [target]
        try workspace.attach(urls, to: target.id, title: "", dreams: dreams)
        let path = try XCTUnwrap(dreams.dreams[0].imagePaths.first)
        let copy = try XCTUnwrap(ImageLibrary.imageURL(for: path)); defer { try? FileManager.default.removeItem(at: copy) }
        try workspace.delete(doc)
        XCTAssertEqual(max(try imageDimensions(copy).width, try imageDimensions(copy).height), 4096)
        XCTAssertThrowsError(try workspace.attach(urls, to: UUID(), title: "", dreams: dreams))
    }
    func testCancelledImportHasNoDraftAndSaveFailureIsReported() async throws {
        let root = try testCollageRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let workspace = CollageStore(root: root)
        let importer = CollageImportSession(); let service = FakePhotoLibrary()
        importer.run(ids: ["a", "b"], kind: .grid, groupID: nil, name: "Cancel", language: .chinese, service: service, store: workspace) { _ in XCTFail("Cancelled import must not commit") }
        importer.close()
        while importer.running { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(workspace.documents.isEmpty)
        var doc = CollageDocument(name: "Fail", kind: .poster); doc.layers = [try testPhoto(workspace.directory(doc.id))]; try workspace.save(doc)
        let editor = CollageEditorModel(document: doc, store: workspace)
        try FileManager.default.removeItem(at: workspace.directory(doc.id))
        editor.apply { $0.title = "Not saved" }
        XCTAssertNotNil(editor.error)
        XCTAssertNotEqual(workspace.documents.first?.title, "Not saved")
        editor.close()
    }
}
