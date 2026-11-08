import UIKit
import ImageIO
import CoreImage
import UniformTypeIdentifiers

enum CollageError: LocalizedError {
    case missingImage, invalidDocument, tooLong, writeFailed, accessDenied
    var errorDescription: String? {
        switch self {
        case .missingImage: return "图片不可用，请重新选择。 / Image unavailable. Choose it again."
        case .invalidDocument: return "请调整照片数量或排版。 / Adjust the photos or layout."
        case .tooLong: return "拼图过长，请减少图片或裁边。 / Reduce the photos or crop the long images."
        case .writeFailed: return "保存失败，请检查可用空间。 / Could not save. Check available space."
        case .accessDenied: return "未获准保存照片，请在设置中开启。 / Allow saving photos in Settings."
        }
    }
}

enum CollageFileFormat: String, CaseIterable, Identifiable { case jpeg = "JPEG", png = "PNG"; var id: String { rawValue }; var suffix: String { self == .jpeg ? "jpg" : "png" } }

/// File-oriented rendering: only one decoded source and one output page at a time.
enum CollageRenderer {
    private static let ciContext = CIContext(options: [.cacheIntermediates: false])
    static func color(_ hex: String) -> UIColor {
        let n = UInt32(hex, radix: 16) ?? 0xFFFFFF
        return UIColor(red: CGFloat((n >> 16)&255)/255, green: CGFloat((n >> 8)&255)/255, blue: CGFloat(n&255)/255, alpha: 1)
    }
    static func load(_ url: URL, maxPixel: Int) throws -> UIImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixel), kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { throw CollageError.missingImage }
        return UIImage(cgImage: image)
    }
    static func assetURL(_ file: String, root: URL) throws -> URL {
        let url = root.appendingPathComponent(file).standardizedFileURL
        guard file.hasPrefix("assets/"), url.path.hasPrefix(root.standardizedFileURL.path + "/"), FileManager.default.fileExists(atPath: url.path) else { throw CollageError.missingImage }
        return url
    }
    static func drawText(_ text: String, rect: CGRect, size: CGFloat, color: UIColor = .black, bold: Bool = false) {
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center; paragraph.lineBreakMode = .byWordWrapping
        (text as NSString).draw(in: rect, withAttributes: [.font: UIFont.systemFont(ofSize: max(1, size), weight: bold ? .semibold : .regular), .foregroundColor: color, .paragraphStyle: paragraph])
    }
    static func drawLayer(_ layer: CollageLayer, rect: CGRect, document: CollageDocument, context: CGContext, image: UIImage?) {
        context.saveGState()
        context.translateBy(x: rect.midX, y: rect.midY); context.rotate(by: layer.rotation * .pi / 180)
        let local = CGRect(x: -rect.width/2, y: -rect.height/2, width: rect.width, height: rect.height)
        if layer.isPhoto, let image {
            let radius = min(local.width, local.height) * document.corner
            context.addPath(UIBezierPath(roundedRect: local, cornerRadius: radius).cgPath); context.clip()
            image.draw(in: CollageGeometry.imageRect(layer, in: local))
            if layer.border > 0 {
                let line = min(local.width, local.height)*layer.border
                context.setStrokeColor(color(layer.borderColor).cgColor); context.setLineWidth(line)
                context.addPath(UIBezierPath(roundedRect: local.insetBy(dx: line/2, dy: line/2), cornerRadius: max(0, radius-line/2)).cgPath); context.strokePath()
            }
            let caption = [layer.label, document.dateText].filter { !$0.isEmpty }.joined(separator: " · ")
            if document.kind == .comparison, !caption.isEmpty {
                let height = min(local.height*0.22, min(rect.width, rect.height)*0.18)
                let band = CGRect(x: local.minX, y: local.maxY-height, width: local.width, height: height)
                context.setFillColor(UIColor.black.withAlphaComponent(0.6).cgColor); context.fill(band)
                drawText(caption, rect: band.insetBy(dx: 5, dy: height*0.12), size: height*0.5, color: .white)
            }
        } else if !layer.isPhoto {
            drawText(layer.text, rect: local, size: layer.fontSize * min(CollageGeometry.make(document).size.width, CollageGeometry.make(document).size.height), color: color(layer.textColor))
        }
        context.restoreGState()
    }
    static func drawHeader(_ document: CollageDocument, geometry: CollageGeometry, context: CGContext) {
        guard let box = geometry.header else { return }
        let short = min(geometry.size.width, geometry.size.height)
        drawText(document.title, rect: CGRect(x: box.minX, y: box.minY, width: box.width, height: box.height*0.46), size: short*0.07, color: color("202124"), bold: true)
        drawText([document.dateText, document.subtitle].filter { !$0.isEmpty }.joined(separator: "\n"), rect: CGRect(x: box.minX, y: box.minY+box.height*0.48, width: box.width, height: box.height*0.52), size: short*0.032, color: color("55555F"))
    }
    static func render(_ doc: CollageDocument, root: URL, geometry: CollageGeometry, page: CGRect, outputScale: CGFloat = 1, cached: [UUID: UIImage]? = nil) throws -> UIImage {
        guard page.width > 0, page.height > 0, page.width.isFinite, page.height.isFinite else { throw CollageError.invalidDocument }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let output = CGSize(width: max(1, (page.width*outputScale).rounded()), height: max(1, (page.height*outputScale).rounded()))
        var failure: Error?
        let image = UIGraphicsImageRenderer(size: output, format: format).image { target in
            let ctx = target.cgContext
            ctx.setFillColor(color(doc.background).cgColor); ctx.fill(CGRect(origin: .zero, size: output))
            ctx.scaleBy(x: outputScale, y: outputScale); ctx.translateBy(x: -page.minX, y: -page.minY)
            drawHeader(doc, geometry: geometry, context: ctx)
            for p in geometry.placements {
                if Task.isCancelled { failure = CancellationError(); break }
                if doc.kind == .strip && !p.rect.intersects(page) { continue }
                // Rotated free layers can intersect even when their unrotated rect does not.
                let reach = hypot(p.rect.width, p.rect.height)/2
                let footprint = CGRect(x: p.rect.midX-reach, y: p.rect.midY-reach, width: reach*2, height: reach*2)
                guard footprint.intersects(page) else { continue }
                do {
                    try autoreleasepool {
                        if doc.kind == .strip, cached == nil, p.layer.file != nil {
                            try drawStripRegion(p, document: doc, root: root, page: page, scale: outputScale, context: ctx)
                            return
                        }
                        let bitmap: UIImage?
                        if let file = p.layer.file {
                            if let cached { guard let value = cached[p.id] else { throw CollageError.missingImage }; bitmap = value }
                            else {
                                let maxPixel = Int(min(4096, max(p.rect.width, p.rect.height)*outputScale*p.layer.zoom*2))
                                bitmap = try load(assetURL(file, root: root), maxPixel: maxPixel)
                            }
                        } else { bitmap = nil }
                        drawLayer(p.layer, rect: p.rect, document: doc, context: ctx, image: bitmap)
                    }
                } catch { failure = error; break }
            }
        }
        if let failure { throw failure }
        return image
    }
    private static func drawStripRegion(_ placement: CollagePlacement, document: CollageDocument, root: URL, page: CGRect, scale: CGFloat, context: CGContext) throws {
        let layer = placement.layer
        let clipped = placement.rect.intersection(page)
        guard !clipped.isNull, clipped.width > 0, clipped.height > 0, let file = layer.file,
              let image = CIImage(contentsOf: try assetURL(file, root: root), options: [.applyOrientationProperty: true]) else { throw CollageError.missingImage }
        let destination = CollageGeometry.imageRect(layer, in: placement.rect)
        let origin = image.extent.origin
        let sx = image.extent.width/destination.width, sy = image.extent.height/destination.height
        let region = CGRect(x: origin.x+(clipped.minX-destination.minX)*sx,
                            y: origin.y+image.extent.height-(clipped.maxY-destination.minY)*sy,
                            width: clipped.width*sx, height: clipped.height*sy).intersection(image.extent)
        let transform = CGAffineTransform(scaleX: scale/sx, y: scale/sy)
        let resized = image.cropped(to: region).transformed(by: transform)
        guard let bitmap = ciContext.createCGImage(resized, from: region.applying(transform)) else { throw CollageError.missingImage }
        context.saveGState()
        context.addPath(UIBezierPath(roundedRect: placement.rect, cornerRadius: min(placement.rect.width, placement.rect.height)*document.corner).cgPath); context.clip()
        UIImage(cgImage: bitmap).draw(in: clipped)
        if layer.border > 0 {
            context.setLineWidth(min(placement.rect.width, placement.rect.height)*layer.border)
            context.setStrokeColor(color(layer.borderColor).cgColor); context.stroke(placement.rect)
        }
        context.restoreGState()
    }
    static func export(_ doc: CollageDocument, root: URL, longEdge: Int, fileFormat: CollageFileFormat, progress: @escaping @Sendable (Double) -> Void) async throws -> [URL] {
        guard doc.isValidCount else { throw CollageError.invalidDocument }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("collage-export-"+UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            let geometry = CollageGeometry.make(doc)
            let pages = doc.kind == .strip ? geometry.pages() : [CGRect(origin: .zero, size: geometry.size)]
            guard !pages.isEmpty else { throw CollageError.tooLong }
            var urls: [URL] = []
            for (index, page) in pages.enumerated() {
                try Task.checkCancellation()
                let url = folder.appendingPathComponent("\(index+1)."+fileFormat.suffix)
                try autoreleasepool {
                    let scale = doc.kind == .strip ? 1 : CGFloat(longEdge)/max(page.width, page.height)
                    let image = try render(doc, root: root, geometry: geometry, page: page, outputScale: scale)
                    try Task.checkCancellation()
                    guard let cg = image.cgImage, let target = CGImageDestinationCreateWithURL(url as CFURL, (fileFormat == .jpeg ? UTType.jpeg.identifier : UTType.png.identifier) as CFString, 1, nil) else { throw CollageError.writeFailed }
                    CGImageDestinationAddImage(target, cg, [kCGImageDestinationLossyCompressionQuality: 0.94] as CFDictionary)
                    guard CGImageDestinationFinalize(target) else { throw CollageError.writeFailed }
                }
                urls.append(url); progress(Double(index+1)/Double(pages.count))
                await Task.yield()
            }
            try Task.checkCancellation()
            return urls
        } catch { try? FileManager.default.removeItem(at: folder); throw error }
    }
    static func cleanExport(_ urls: [URL]) {
        guard let folder = urls.first?.deletingLastPathComponent(), folder.lastPathComponent.hasPrefix("collage-export-") else { return }
        try? FileManager.default.removeItem(at: folder)
    }
}
