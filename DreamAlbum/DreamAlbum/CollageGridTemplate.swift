import Foundation
import CoreGraphics

/// Every split fills its parent; incomplete rows expand instead of leaving holes.
enum CollageGridTemplate: String, CaseIterable, Identifiable, Sendable {
    case rows, columns, heroTop, heroLeft, heroBottom, heroRight
    var id: String { rawValue }
    static func available(for count: Int) -> [Self] {
        guard (2...9).contains(count) else { return [] }
        return count == 2 ? [.rows, .columns] : allCases
    }
    func title(_ language: AppLanguage, count: Int) -> String {
        let zh: String, en: String
        switch self {
        case .rows: zh = count == 2 ? "左右" : "横向均衡"; en = count == 2 ? "Side by side" : "Rows"
        case .columns: zh = count == 2 ? "上下" : "纵向均衡"; en = count == 2 ? "Stacked" : "Columns"
        case .heroTop: zh = "主图在上"; en = "Hero above"
        case .heroLeft: zh = "主图在左"; en = "Hero left"
        case .heroBottom: zh = "主图在下"; en = "Hero below"
        case .heroRight: zh = "主图在右"; en = "Hero right"
        }
        return language == .english ? en : zh
    }
    func rects(in area: CGRect, count: Int, gap: CGFloat) -> [CGRect] {
        guard count > 0 else { return [] }
        func rows(_ area: CGRect, _ count: Int) -> [CGRect] {
            let rowCount = max(1, Int(Double(count).squareRoot().rounded()))
            let height = (area.height - gap * CGFloat(rowCount-1)) / CGFloat(rowCount)
            return (0..<rowCount).flatMap { row -> [CGRect] in
                let columns = count / rowCount + (row < count % rowCount ? 1 : 0)
                let width = (area.width - gap * CGFloat(columns-1)) / CGFloat(columns)
                return (0..<columns).map { column in
                    CGRect(x: area.minX + CGFloat(column)*(width+gap), y: area.minY + CGFloat(row)*(height+gap), width: width, height: height)
                }
            }
        }
        switch self {
        case .rows: return rows(area, count)
        case .columns:
            return rows(CGRect(x: area.minY, y: area.minX, width: area.height, height: area.width), count)
                .map { CGRect(x: $0.minY, y: $0.minX, width: $0.height, height: $0.width) }
        default:
            guard count > 1 else { return [area] }
            let vertical = self == .heroTop || self == .heroBottom
            let first = self == .heroTop || self == .heroLeft
            let length = (vertical ? area.height : area.width) - gap
            let heroLength = length * 0.55, restLength = length - heroLength
            let start = vertical ? area.minY : area.minX
            let heroStart = first ? start : start + restLength + gap
            let restStart = first ? start + heroLength + gap : start
            let hero = vertical ? CGRect(x: area.minX, y: heroStart, width: area.width, height: heroLength) : CGRect(x: heroStart, y: area.minY, width: heroLength, height: area.height)
            let rest = vertical ? CGRect(x: area.minX, y: restStart, width: area.width, height: restLength) : CGRect(x: restStart, y: area.minY, width: restLength, height: area.height)
            return [hero] + (vertical ? Self.rows : Self.columns).rects(in: rest, count: count-1, gap: gap)
        }
    }
}

/// One local transaction; cancelling a crop never mutates the draft or undo history.
struct CollageGridCrop: Identifiable {
    var layer: CollageLayer
    let aspect: CGFloat
    var id: UUID { layer.id }
    mutating func reset() { layer.zoom = 1; layer.offsetX = 0; layer.offsetY = 0; layer.photoFit = .fill }
    mutating func transform(from base: CollageLayer, translation: CGSize, scale: CGFloat, box: CGSize) {
        guard layer.photoFit != .fit else { return }
        layer.zoom = min(5, max(1, base.zoom * scale))
        layer.offsetX = base.offsetX; layer.offsetY = base.offsetY
        let rect = CollageGeometry.imageRect(layer, in: CGRect(origin: .zero, size: box))
        let excessX = max(0, rect.width * (1-layer.cropLeft-layer.cropRight) - box.width)
        let excessY = max(0, rect.height * (1-layer.cropTop-layer.cropBottom) - box.height)
        layer.offsetX = excessX > 0 ? min(1, max(-1, base.offsetX + translation.width*2/excessX)) : 0
        layer.offsetY = excessY > 0 ? min(1, max(-1, base.offsetY + translation.height*2/excessY)) : 0
    }
}
