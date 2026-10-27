import AppKit
import CoreGraphics
import Foundation

struct Shot {
    let source: String
    let output: String
    let kicker: String
    let title: String
    let subtitle: String
}

let root = FileManager.default.currentDirectoryPath
let fm = FileManager.default

func image(_ path: String) -> NSImage? { NSImage(contentsOfFile: path) }

func font(_ size: CGFloat, weight: NSFont.Weight) -> NSFont {
    NSFont.systemFont(ofSize: size, weight: weight)
}

func drawText(_ text: String, in rect: CGRect, font: NSFont, color: NSColor, alignment: NSTextAlignment = .left) {
    let style = NSMutableParagraphStyle()
    style.alignment = alignment
    style.lineBreakMode = .byWordWrapping
    (text as NSString).draw(in: rect, withAttributes: [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: style
    ])
}

func roundedRect(_ rect: CGRect, radius: CGFloat, fill: NSColor, stroke: NSColor? = nil, width: CGFloat = 0) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    fill.setFill(); path.fill()
    if let stroke {
        stroke.setStroke(); path.lineWidth = width; path.stroke()
    }
}

func makeShot(_ shot: Shot, canvasSize: CGSize, screenshotWidth: CGFloat) throws {
    guard let source = image(shot.source) else { throw NSError(domain: "Screenshot", code: 1) }
    let canvas = NSImage(size: canvasSize)
    canvas.lockFocus()

    let w = canvasSize.width
    let h = canvasSize.height
    NSColor(calibratedRed: 0.925, green: 0.965, blue: 0.985, alpha: 1).setFill()
    NSRect(origin: .zero, size: canvasSize).fill()

    // Small editorial color marks keep the cover expressive without competing with the UI.
    NSColor(calibratedRed: 0.15, green: 0.58, blue: 0.92, alpha: 0.16).setFill()
    NSBezierPath(ovalIn: CGRect(x: w - 280, y: h - 250, width: 360, height: 360)).fill()
    NSColor(calibratedRed: 1.0, green: 0.39, blue: 0.49, alpha: 0.13).setFill()
    NSBezierPath(ovalIn: CGRect(x: -150, y: h - 610, width: 330, height: 330)).fill()

    let isPad = canvasSize.width > 1500
    let left: CGFloat = isPad ? 150 : 120
    let top = h - (isPad ? 315 : 350)
    drawText(shot.kicker.uppercased(), in: CGRect(x: left, y: top + 180, width: w - left * 2, height: 36), font: font(isPad ? 30 : 26, weight: .semibold), color: NSColor(calibratedRed: 0.10, green: 0.28, blue: 0.40, alpha: 0.72))
    drawText(shot.title, in: CGRect(x: left, y: top + 65, width: w - left * 2, height: 115), font: font(isPad ? 72 : 64, weight: .bold), color: NSColor(calibratedRed: 0.04, green: 0.12, blue: 0.18, alpha: 1))
    drawText(shot.subtitle, in: CGRect(x: left, y: top + 20, width: w - left * 2, height: 45), font: font(isPad ? 30 : 27, weight: .medium), color: NSColor(calibratedRed: 0.10, green: 0.28, blue: 0.40, alpha: 0.76))

    let cardX = (w - screenshotWidth) / 2
    let cardY: CGFloat = isPad ? 175 : 150
    let cardH = screenshotWidth * (source.size.height / source.size.width)
    let cardRect = CGRect(x: cardX, y: cardY, width: screenshotWidth, height: cardH)
    let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.20); shadow.shadowBlurRadius = 34; shadow.shadowOffset = NSSize(width: 0, height: -12)
    NSGraphicsContext.current?.saveGraphicsState(); shadow.set()
    roundedRect(cardRect.insetBy(dx: -10, dy: -10), radius: isPad ? 42 : 38, fill: NSColor.white.withAlphaComponent(0.95))
    NSGraphicsContext.current?.restoreGraphicsState()

    let clip = NSBezierPath(roundedRect: cardRect, xRadius: isPad ? 34 : 30, yRadius: isPad ? 34 : 30)
    clip.addClip()
    source.draw(in: cardRect, from: NSRect(origin: .zero, size: source.size), operation: .sourceOver, fraction: 1)
    canvas.unlockFocus()

    guard let tiff = canvas.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let data = rep.representation(using: .png, properties: [:]) else { throw NSError(domain: "Screenshot", code: 2) }
    try fm.createDirectory(atPath: (shot.output as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    try data.write(to: URL(fileURLWithPath: shot.output))
}

let iphoneDir = "\(root)/AppStoreScreenshots/appstore-ready-20260714/iphone-6-9"
let ipadDir = "\(root)/AppStoreScreenshots/appstore-ready-20260714/ipad-13"
let outIphone = "\(root)/AppStoreScreenshots/appstore-upload-20260716/iphone-6-9"
let outIpad = "\(root)/AppStoreScreenshots/appstore-upload-20260716/ipad-13"

let iphoneShots = [
    Shot(source: "\(iphoneDir)/iphone-01-dream-wall.png", output: "\(outIphone)/01-dream-wall.png", kicker: "Dream Album", title: "让梦想有画面", subtitle: "See it clearly. Keep moving forward."),
    Shot(source: "\(iphoneDir)/iphone-02-record.png", output: "\(outIphone)/02-add-record.png", kicker: "Dream Album", title: "把每一步留下来", subtitle: "Turn small moments into a story worth keeping."),
    Shot(source: "\(iphoneDir)/iphone-03-footprint.png", output: "\(outIphone)/03-growth-footprint.png", kicker: "Dream Album", title: "回望每一步成长", subtitle: "Your progress, collected in one beautiful place."),
    Shot(source: "\(iphoneDir)/iphone-04-profile.png", output: "\(outIphone)/04-profile.png", kicker: "Dream Album", title: "只属于你的梦想相册", subtitle: "A calm space for dreams, photos, and memories.")
]

let ipadShots = [
    Shot(source: "\(ipadDir)/ipad-01-dream-wall.png", output: "\(outIpad)/01-dream-wall.png", kicker: "Dream Album for iPad", title: "让梦想有画面", subtitle: "See your dreams clearly, at a glance."),
    Shot(source: "\(ipadDir)/ipad-04-add-record.png", output: "\(outIpad)/02-add-record.png", kicker: "Dream Album for iPad", title: "把每一步留下来", subtitle: "Add a thought, a photo, or a moment of progress."),
    Shot(source: "\(ipadDir)/ipad-03-growth-footprint.png", output: "\(outIpad)/03-growth-footprint.png", kicker: "Dream Album for iPad", title: "回望每一步成长", subtitle: "A visual timeline of the moments that moved you."),
    Shot(source: "\(ipadDir)/ipad-02-profile.png", output: "\(outIpad)/04-profile.png", kicker: "Dream Album for iPad", title: "只属于你的梦想相册", subtitle: "Simple, personal, and made to grow with you.")
]

for shot in iphoneShots { try makeShot(shot, canvasSize: CGSize(width: 1320, height: 2868), screenshotWidth: 1000) }
for shot in ipadShots { try makeShot(shot, canvasSize: CGSize(width: 2064, height: 2752), screenshotWidth: 1600) }
print("Generated 8 App Store screenshots")
