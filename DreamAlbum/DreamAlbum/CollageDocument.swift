import Foundation
import CoreGraphics

enum CollageKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case grid, strip, comparison, poster, freeform
    var id: String { rawValue }
    var limits: ClosedRange<Int> {
        switch self { case .grid: return 2...9; case .strip: return 2...20; case .comparison: return 2...4; case .poster: return 1...9; case .freeform: return 1...20 }
    }
    func title(_ language: AppLanguage) -> String {
        let zh = ["宫格拼图", "长图拼接", "对比拼图", "梦想海报", "自由拼贴"]
        let en = ["Grid", "Long collage", "Comparison", "Dream poster", "Free collage"]
        return (language == .english ? en : zh)[Self.allCases.firstIndex(of: self)!]
    }
    var symbol: String {
        switch self { case .grid: return "square.grid.2x2"; case .strip: return "rectangle.split.1x2"; case .comparison: return "rectangle.split.2x1"; case .poster: return "photo.artframe"; case .freeform: return "square.3.layers.3d" }
    }
}

enum CollageRatio: String, CaseIterable, Codable, Identifiable, Sendable {
    case square = "1:1", portrait = "3:4", landscape = "4:3", story = "9:16", wide = "16:9"
    var id: String { rawValue }
    var value: Double {
        switch self { case .square: return 1; case .portrait: return 0.75; case .landscape: return 4.0/3; case .story: return 9.0/16; case .wide: return 16.0/9 }
    }
}

struct CollageLayer: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var file: String? = nil
    var pixelWidth: Double = 1
    var pixelHeight: Double = 1
    var text = ""
    var label = ""
    var x = 0.15
    var y = 0.15
    var width = 0.7
    var height = 0.55
    var rotation = 0.0
    var zoom = 1.0
    var offsetX = 0.0
    var offsetY = 0.0
    var cropTop = 0.0
    var cropBottom = 0.0
    var cropLeft = 0.0
    var cropRight = 0.0
    var border = 0.0
    var borderColor = "FFFFFF"
    var locked = false
    var fontSize = 0.045
    var textColor = "202124"
    var isPhoto: Bool { file != nil }
    var croppedRatio: Double { max(1, pixelWidth) * max(0.1, 1-cropLeft-cropRight) / (max(1, pixelHeight) * max(0.1, 1-cropTop-cropBottom)) }
}

struct CollageDocument: Codable, Equatable, Identifiable, Sendable {
    var schemaVersion = 1
    var id = UUID()
    var name: String
    var kind: CollageKind
    var sourceGroupID: String?
    var updatedAt = Date()
    var ratio: CollageRatio = .square
    var layout = 0
    var horizontal = false
    var spacing = 0.015
    var margin = 0.035
    var corner = 0.015
    var background = "FFFFFF"
    var title = ""
    var subtitle = ""
    var dateText = ""
    var layers: [CollageLayer] = []
    var hasFreeLayout = false
    var photoCount: Int { layers.filter(\.isPhoto).count }
    var isValidCount: Bool { kind.limits.contains(photoCount) }
    mutating func setKind(_ kind: CollageKind) {
        self.kind = kind; layout = 0
        ratio = kind == .poster ? .portrait : (kind == .comparison ? .landscape : .square)
        // Strips use axis-aligned source regions for both preview and paged export.
        if kind == .strip { for i in layers.indices where layers[i].isPhoto { layers[i].rotation = 0 } }
    }
    mutating func arrangeFreeLayers() {
        hasFreeLayout = true
        let photos = layers.indices.filter { layers[$0].isPhoto }
        for (i, index) in photos.enumerated() {
            let columns = photos.count <= 2 ? 1 : 2
            let rows = Int(ceil(Double(photos.count) / Double(columns)))
            layers[index].width = 0.82 / Double(columns)
            layers[index].height = 0.82 / Double(max(rows, 1))
            layers[index].x = 0.07 + Double(i % columns) * 0.43
            layers[index].y = 0.07 + Double(i / columns) * 0.86 / Double(max(rows, 1))
        }
    }
}

struct CollagePlacement: Identifiable {
    let layer: CollageLayer
    let rect: CGRect
    var id: UUID { layer.id }
}

struct CollageGeometry {
    let size: CGSize
    let placements: [CollagePlacement]
    let header: CGRect?
    static func make(_ doc: CollageDocument, shortSide: CGFloat = 1440) -> Self {
        let photos = doc.layers.filter(\.isPhoto)
        if doc.kind == .strip {
            let cross = shortSide
            let inset = cross * doc.margin, gap = cross * doc.spacing
            let available = max(1, cross - inset*2)
            var offset = inset
            var placements: [CollagePlacement] = []
            for photo in photos {
                let length = doc.horizontal ? available * photo.croppedRatio : available / photo.croppedRatio
                let rect = doc.horizontal ? CGRect(x: offset, y: inset, width: length, height: available) : CGRect(x: inset, y: offset, width: available, height: length)
                placements.append(.init(layer: photo, rect: rect)); offset += length + gap
            }
            let length = max(cross, offset - (photos.isEmpty ? 0 : gap) + inset)
            return Self(size: doc.horizontal ? CGSize(width: length, height: cross) : CGSize(width: cross, height: length), placements: placements, header: nil)
        }
        let ratio = doc.ratio.value
        let size = ratio >= 1 ? CGSize(width: shortSide * ratio, height: shortSide) : CGSize(width: shortSide, height: shortSide / ratio)
        let short = min(size.width, size.height), inset = short * doc.margin, gap = short * doc.spacing
        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
        if doc.kind == .freeform {
            return Self(size: size, placements: doc.layers.map { .init(layer: $0, rect: CGRect(x: $0.x*size.width, y: $0.y*size.height, width: $0.width*size.width, height: $0.height*size.height)) }, header: nil)
        }
        var content = bounds
        var header: CGRect?
        if doc.kind == .poster {
            let height = bounds.height * (doc.layout == 2 ? 0.25 : 0.21)
            header = CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: height)
            content.origin.y += height + gap; content.size.height -= height + gap
        }
        let n = photos.count
        var rects: [CGRect] = []
        func grid(_ area: CGRect, count: Int, columns: Int) -> [CGRect] {
            guard count > 0 else { return [] }
            let rows = Int(ceil(Double(count) / Double(columns)))
            let w = max(1, (area.width-gap*CGFloat(columns-1))/CGFloat(columns))
            let h = max(1, (area.height-gap*CGFloat(rows-1))/CGFloat(rows))
            return (0..<count).map { CGRect(x: area.minX+CGFloat($0 % columns)*(w+gap), y: area.minY+CGFloat($0/columns)*(h+gap), width: w, height: h) }
        }
        if doc.kind == .comparison {
            rects = grid(content, count: n, columns: doc.layout == 1 ? 1 : (doc.layout == 2 ? 2 : max(n, 1)))
        } else if n > 1 && (doc.layout != 0 || doc.kind == .poster) {
            let verticalHero = doc.layout != 1
            let hero = verticalHero ? CGRect(x: content.minX, y: content.minY, width: content.width, height: (content.height-gap)*0.62) : CGRect(x: content.minX, y: content.minY, width: (content.width-gap)*0.62, height: content.height)
            let rest = verticalHero ? CGRect(x: content.minX, y: hero.maxY+gap, width: content.width, height: content.maxY-hero.maxY-gap) : CGRect(x: hero.maxX+gap, y: content.minY, width: content.maxX-hero.maxX-gap, height: content.height)
            rects = [hero] + grid(rest, count: n-1, columns: verticalHero ? min(n-1, 3) : (n > 5 ? 2 : 1))
        } else {
            rects = grid(content, count: n, columns: max(1, Int(ceil(sqrt(Double(n))))))
        }
        var placements = zip(photos, rects).map { CollagePlacement(layer: $0, rect: $1) }
        placements += doc.layers.filter { !$0.isPhoto }.map { .init(layer: $0, rect: CGRect(x: $0.x*size.width, y: $0.y*size.height, width: $0.width*size.width, height: $0.height*size.height)) }
        return Self(size: size, placements: placements, header: header)
    }
    func pages(maxLength: CGFloat = 16000) -> [CGRect] {
        let horizontal = size.width > maxLength
        let length = horizontal ? size.width : size.height
        let count = Int(ceil(length/maxLength))
        guard count <= 100 else { return [] }
        return (0..<max(1, count)).map { index in
            let offset = CGFloat(index)*maxLength
            return horizontal ? CGRect(x: offset, y: 0, width: min(maxLength, size.width-offset), height: size.height) : CGRect(x: 0, y: offset, width: size.width, height: min(maxLength, size.height-offset))
        }
    }
    static func imageRect(_ layer: CollageLayer, in box: CGRect) -> CGRect {
        let width = max(1, layer.pixelWidth), height = max(1, layer.pixelHeight)
        let cw = width * max(0.1, 1-layer.cropLeft-layer.cropRight)
        let ch = height * max(0.1, 1-layer.cropTop-layer.cropBottom)
        let scale = max(box.width/cw, box.height/ch) * layer.zoom
        let w = width*scale, h = height*scale
        let visibleW = cw*scale, visibleH = ch*scale
        return CGRect(x: box.midX-visibleW/2-layer.cropLeft*w + layer.offsetX*max(0, visibleW-box.width)/2,
                      y: box.midY-visibleH/2-layer.cropTop*h + layer.offsetY*max(0, visibleH-box.height)/2,
                      width: w, height: h)
    }
}
