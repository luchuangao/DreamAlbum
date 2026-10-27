import Foundation
import UIKit

enum DreamWidgetShared {
    static let appGroupID = "group.com.luchuangao.mengxiangxiangce"
    static let snapshotFileName = "dream-widget-snapshot.json"
    static let coverFileName = "dream-widget-cover.jpg"
    static let smallAlbumFileName = "dream-widget-album-small.jpg"
    static let mediumAlbumFileName = "dream-widget-album-medium.jpg"
}

struct DreamWidgetSnapshot: Codable {
    var title: String
    var visionText: String
    var latestRecord: String
    var recordCount: Int
    var imageCount: Int
    var updatedAt: Date

    static let empty = DreamWidgetSnapshot(
        title: "梦想相册",
        visionText: "让梦想变具体，让未来在进行时",
        latestRecord: "添加一个梦想，让它出现在手机屏幕上",
        recordCount: 0,
        imageCount: 0,
        updatedAt: Date()
    )
}

enum DreamWidgetSnapshotStore {
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: DreamWidgetShared.appGroupID)
    }

    static var snapshotURL: URL? {
        containerURL?.appendingPathComponent(DreamWidgetShared.snapshotFileName)
    }

    static var coverURL: URL? {
        containerURL?.appendingPathComponent(DreamWidgetShared.coverFileName)
    }

    static var smallAlbumURL: URL? {
        containerURL?.appendingPathComponent(DreamWidgetShared.smallAlbumFileName)
    }

    static var mediumAlbumURL: URL? {
        containerURL?.appendingPathComponent(DreamWidgetShared.mediumAlbumFileName)
    }

    static func load() -> DreamWidgetSnapshot {
        guard let snapshotURL,
              let data = try? Data(contentsOf: snapshotURL),
              let snapshot = try? JSONDecoder().decode(DreamWidgetSnapshot.self, from: data) else {
            return .empty
        }
        return snapshot
    }

    static func write(snapshot: DreamWidgetSnapshot, coverImage: UIImage?) {
        guard let snapshotURL else { return }
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: snapshotURL, options: .atomic)
            if let coverImage,
               let coverURL,
               let imageData = coverImage.resizedForWidget().jpegData(compressionQuality: 0.82) {
                try imageData.write(to: coverURL, options: .atomic)
            }
            if let smallAlbumURL,
               let smallData = renderAlbumPreview(snapshot: snapshot, coverImage: coverImage, size: CGSize(width: 720, height: 720)).jpegData(compressionQuality: 0.88) {
                try smallData.write(to: smallAlbumURL, options: .atomic)
            }
            if let mediumAlbumURL,
               let mediumData = renderAlbumPreview(snapshot: snapshot, coverImage: coverImage, size: CGSize(width: 1440, height: 720)).jpegData(compressionQuality: 0.88) {
                try mediumData.write(to: mediumAlbumURL, options: .atomic)
            }
        } catch {
            return
        }
    }

    private static func renderAlbumPreview(snapshot: DreamWidgetSnapshot, coverImage: UIImage?, size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            let cg = context.cgContext
            let bounds = CGRect(origin: .zero, size: size)
            let isWide = size.width > size.height
            let radius = min(size.width, size.height) * 0.12

            if !isWide {
                renderSquareHomeAlbum(snapshot: snapshot, coverImage: coverImage, in: bounds, context: cg)
                return
            }

            UIColor(red: 0.86, green: 0.94, blue: 0.99, alpha: 1).setFill()
            UIBezierPath(roundedRect: bounds, cornerRadius: radius).fill()

            let cardRect = bounds.insetBy(dx: size.width * 0.045, dy: size.height * 0.045)
            UIColor.white.withAlphaComponent(0.98).setFill()
            UIBezierPath(roundedRect: cardRect, cornerRadius: radius * 0.72).fill()

            cg.saveGState()

            let imageRect: CGRect
            if isWide {
                imageRect = CGRect(
                    x: cardRect.minX + size.width * 0.018,
                    y: cardRect.minY + size.height * 0.035,
                    width: cardRect.width * 0.60,
                    height: cardRect.height - size.height * 0.07
                )
            } else {
                imageRect = CGRect(
                    x: cardRect.minX + size.width * 0.04,
                    y: cardRect.minY + size.height * 0.04,
                    width: cardRect.width - size.width * 0.08,
                    height: size.height * 0.51
                )
            }

            UIColor(red: 0.92, green: 0.96, blue: 0.98, alpha: 1).setFill()
            UIBezierPath(roundedRect: imageRect, cornerRadius: radius * 0.45).fill()
            UIBezierPath(roundedRect: imageRect, cornerRadius: radius * 0.45).addClip()
            if let coverImage {
                drawContainedCover(coverImage, in: imageRect.insetBy(dx: size.width * 0.012, dy: size.width * 0.012))
            } else {
                let colors = [UIColor(red: 0.36, green: 0.67, blue: 0.94, alpha: 1).cgColor, UIColor(red: 0.93, green: 0.97, blue: 1, alpha: 1).cgColor]
                let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
                cg.drawLinearGradient(gradient, start: imageRect.origin, end: CGPoint(x: imageRect.maxX, y: imageRect.maxY), options: [])
            }
            cg.restoreGState()

            drawText(snapshot: snapshot, in: bounds, isWide: isWide)
        }
    }

    private static func renderSquareHomeAlbum(snapshot: DreamWidgetSnapshot, coverImage: UIImage?, in bounds: CGRect, context cg: CGContext) {
        if let coverImage {
            drawFilledCover(coverImage, in: bounds)
        } else {
            let colors = [UIColor(red: 0.42, green: 0.72, blue: 0.96, alpha: 1).cgColor, UIColor(red: 0.86, green: 0.94, blue: 0.99, alpha: 1).cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
            cg.drawLinearGradient(gradient, start: bounds.origin, end: CGPoint(x: bounds.maxX, y: bounds.maxY), options: [])
        }

        let topDim = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [UIColor.black.withAlphaComponent(0.04).cgColor, UIColor.clear.cgColor] as CFArray,
            locations: [0, 1]
        )!
        cg.drawLinearGradient(topDim, start: CGPoint(x: bounds.midX, y: bounds.minY), end: CGPoint(x: bounds.midX, y: bounds.height * 0.32), options: [])

        let bottomDim = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.70).cgColor] as CFArray,
            locations: [0, 1]
        )!
        cg.drawLinearGradient(bottomDim, start: CGPoint(x: bounds.midX, y: bounds.height * 0.36), end: CGPoint(x: bounds.midX, y: bounds.maxY), options: [])

        let inset = bounds.width * 0.095
        let titleRect = CGRect(x: inset, y: bounds.height * 0.58, width: bounds.width - inset * 2, height: bounds.height * 0.14)
        let bodyRect = CGRect(x: inset, y: bounds.height * 0.72, width: bounds.width - inset * 2.2, height: bounds.height * 0.15)
        let metaRect = CGRect(x: inset, y: bounds.height * 0.875, width: bounds.width - inset * 2, height: bounds.height * 0.06)

        let title = snapshot.title.isEmpty ? "梦想相册" : snapshot.title
        title.draw(
            with: titleRect,
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: [
                .font: UIFont.systemFont(ofSize: 54, weight: .black),
                .foregroundColor: UIColor.white
            ],
            context: nil
        )

        let subtitle = snapshot.visionText.isEmpty ? (snapshot.latestRecord.isEmpty ? "让梦想先有一张画面" : snapshot.latestRecord) : snapshot.visionText
        subtitle.draw(
            with: bodyRect,
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: [
                .font: UIFont.systemFont(ofSize: 30, weight: .bold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.92)
            ],
            context: nil
        )

        "\(snapshot.recordCount) 条记录 · \(snapshot.imageCount) 张画面".draw(
            with: metaRect,
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: [
                .font: UIFont.systemFont(ofSize: 22, weight: .heavy),
                .foregroundColor: UIColor.white.withAlphaComponent(0.76)
            ],
            context: nil
        )
    }

    private static func drawFilledCover(_ image: UIImage, in rect: CGRect) {
        let imageSize = image.size
        let scale = max(rect.width / max(imageSize.width, 1), rect.height / max(imageSize.height, 1))
        let drawSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let drawRect = CGRect(
            x: rect.midX - drawSize.width / 2,
            y: rect.midY - drawSize.height / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        image.draw(in: drawRect)
    }

    private static func drawContainedCover(_ image: UIImage, in rect: CGRect) {
        let imageSize = image.size
        let scale = min(rect.width / max(imageSize.width, 1), rect.height / max(imageSize.height, 1))
        let drawSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let drawRect = CGRect(
            x: rect.midX - drawSize.width / 2,
            y: rect.midY - drawSize.height / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        image.draw(in: drawRect)
    }

    private static func drawText(snapshot: DreamWidgetSnapshot, in bounds: CGRect, isWide: Bool) {
        let ink = UIColor(red: 0.05, green: 0.12, blue: 0.17, alpha: 1)
        let muted = UIColor(red: 0.28, green: 0.38, blue: 0.44, alpha: 1)
        let titleColor = ink
        let bodyColor = muted

        let titleRect: CGRect
        let bodyRect: CGRect
        let badgeRect: CGRect
        if isWide {
            titleRect = CGRect(x: bounds.width * 0.70, y: bounds.height * 0.28, width: bounds.width * 0.23, height: bounds.height * 0.18)
            bodyRect = CGRect(x: bounds.width * 0.70, y: bounds.height * 0.50, width: bounds.width * 0.23, height: bounds.height * 0.18)
            badgeRect = CGRect(x: bounds.width * 0.70, y: bounds.height * 0.14, width: bounds.width * 0.20, height: bounds.height * 0.11)
        } else {
            titleRect = CGRect(x: bounds.width * 0.12, y: bounds.height * 0.66, width: bounds.width * 0.74, height: bounds.height * 0.11)
            bodyRect = CGRect(x: bounds.width * 0.12, y: bounds.height * 0.78, width: bounds.width * 0.74, height: bounds.height * 0.08)
            badgeRect = CGRect(x: bounds.width * 0.12, y: bounds.height * 0.12, width: bounds.width * 0.46, height: bounds.height * 0.085)
        }

        drawRoundedBadge(
            text: "\(snapshot.recordCount) 条记录 · \(snapshot.imageCount) 张画面",
            in: badgeRect,
            foreground: UIColor.white,
            fill: UIColor(red: 0.20, green: 0.47, blue: 1.0, alpha: 0.92)
        )

        let title = snapshot.title.isEmpty ? "梦想相册" : snapshot.title
        title.draw(
            with: titleRect,
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: [
                .font: UIFont.systemFont(ofSize: isWide ? 58 : 44, weight: .black),
                .foregroundColor: titleColor
            ],
            context: nil
        )

        let subtitle = snapshot.latestRecord.isEmpty ? (snapshot.visionText.isEmpty ? "让梦想变具体，让未来在进行时" : snapshot.visionText) : snapshot.latestRecord
        subtitle.draw(
            with: bodyRect,
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: [
                .font: UIFont.systemFont(ofSize: isWide ? 25 : 21, weight: .bold),
                .foregroundColor: bodyColor
            ],
            context: nil
        )
    }

    private static func drawRoundedBadge(text: String, in rect: CGRect, foreground: UIColor, fill: UIColor) {
        fill.setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2).fill()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        text.draw(
            with: rect.insetBy(dx: rect.height * 0.32, dy: rect.height * 0.25),
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: [
                .font: UIFont.systemFont(ofSize: rect.height * 0.34, weight: .black),
                .foregroundColor: foreground,
                .paragraphStyle: paragraph
            ],
            context: nil
        )
    }
}

private extension UIImage {
    func resizedForWidget(maxLength: CGFloat = 900) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxLength else { return self }
        let scale = maxLength / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
