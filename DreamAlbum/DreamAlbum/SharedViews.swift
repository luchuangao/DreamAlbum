import SwiftUI
import UIKit
#if canImport(Lottie)
import Lottie
#endif

enum AlbumFonts {
    static func collageTitle(_ size: CGFloat) -> Font {
        .custom("ZCOOLKuaiLe-Regular", size: size)
    }
}

private struct AlbumBackgroundContrastKey: EnvironmentKey {
    static let defaultValue: BackgroundContrast = .regular
}

extension EnvironmentValues {
    var albumBackgroundContrast: BackgroundContrast {
        get { self[AlbumBackgroundContrastKey.self] }
        set { self[AlbumBackgroundContrastKey.self] = newValue }
    }
}

struct CameraCaptureView: UIViewControllerRepresentable {
    static var isCameraAvailable: Bool {
        #if targetEnvironment(macCatalyst)
        return false
        #else
        return UIImagePickerController.isSourceTypeAvailable(.camera)
        #endif
    }

    let onImage: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage, dismiss: dismiss)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onImage: (UIImage) -> Void
        let dismiss: DismissAction

        init(onImage: @escaping (UIImage) -> Void, dismiss: DismissAction) {
            self.onImage = onImage
            self.dismiss = dismiss
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                onImage(image)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}

enum BackgroundImageAnalyzer {
    static func contrast(choice: BackgroundImageChoice, customPath: String?) -> BackgroundContrast {
        guard let image = image(choice: choice, customPath: customPath) else { return .regular }
        return contrast(for: image)
    }

    private static func image(choice: BackgroundImageChoice, customPath: String?) -> UIImage? {
        if choice == .custom,
           let customPath,
           let url = ImageLibrary.imageURL(for: customPath) {
            return UIImage(contentsOfFile: url.path)
        }
        guard let assetName = choice.assetName else { return nil }
        return UIImage(named: assetName)
    }

    private static func contrast(for image: UIImage) -> BackgroundContrast {
        let size = CGSize(width: 32, height: 32)
        let thumbnail = UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let cgImage = thumbnail.cgImage else { return .regular }

        let width = Int(size.width)
        let height = Int(size.height)
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        pixels.withUnsafeMutableBytes { rawBuffer in
            guard let context = CGContext(
                data: rawBuffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            context.draw(cgImage, in: CGRect(origin: .zero, size: size))
        }

        var totalLuminance = 0.0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let red = Double(pixels[index]) / 255
            let green = Double(pixels[index + 1]) / 255
            let blue = Double(pixels[index + 2]) / 255
            totalLuminance += 0.2126 * red + 0.7152 * green + 0.0722 * blue
        }

        let average = totalLuminance / Double(max(1, width * height))
        if average < 0.36 { return .dark }
        if average > 0.68 { return .light }
        return .regular
    }
}

/// Background preferences remain decodable for old backups. All live screens
/// use the same surface; an old custom image no longer changes page appearance.
struct AlbumBackground: View {
    var body: some View { LibraryStyle.background.ignoresSafeArea() }
}

struct BackgroundReadabilityOverlay: View {
    let contrast: BackgroundContrast

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [topStart, topMiddle, .clear],
                startPoint: .top,
                endPoint: .center
            )

            LinearGradient(
                colors: [.clear, bottomMiddle, bottomEnd],
                startPoint: .center,
                endPoint: .bottom
            )

            if contrast == .dark {
                Color.black.opacity(0.04)
            }
        }
        .allowsHitTesting(false)
    }

    private var topStart: Color {
        switch contrast {
        case .light: return .white.opacity(0.04)
        case .regular: return .white.opacity(0.16)
        case .dark: return .black.opacity(0.46)
        }
    }

    private var topMiddle: Color {
        switch contrast {
        case .light: return .white.opacity(0.01)
        case .regular: return .white.opacity(0.08)
        case .dark: return .black.opacity(0.20)
        }
    }

    private var bottomMiddle: Color {
        switch contrast {
        case .light: return .white.opacity(0.02)
        case .regular: return .white.opacity(0.08)
        case .dark: return .black.opacity(0.18)
        }
    }

    private var bottomEnd: Color {
        switch contrast {
        case .light: return .white.opacity(0.08)
        case .regular: return .white.opacity(0.16)
        case .dark: return .black.opacity(0.36)
        }
    }
}

struct BeachBackground: View {
    var body: some View {
        GeometryReader { proxy in
            Image("BeachVacationBackground")
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .allowsHitTesting(false)
    }
}

struct PorcelainBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.porcelainWhite,
                    Color.porcelainMist,
                    Color(red: 0.90, green: 0.95, blue: 0.99)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            PorcelainBackgroundDoodles()
        }
    }
}

private struct PorcelainBackgroundDoodles: View {
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            ZStack {
                PorcelainMedallion()
                    .frame(width: 230, height: 230)
                    .opacity(0.52)
                    .position(x: width * 0.90, y: height * 0.18)
                PorcelainMedallion()
                    .frame(width: 170, height: 170)
                    .opacity(0.30)
                    .blur(radius: 3)
                    .position(x: width * 0.09, y: height * 0.64)
                WaveLine()
                    .stroke(Color.porcelainBlue.opacity(0.16), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .frame(width: 150, height: 24)
                    .position(x: width * 0.24, y: height * 0.24)
                WaveLine()
                    .stroke(Color.porcelainDeepBlue.opacity(0.12), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .frame(width: 118, height: 24)
                    .rotationEffect(.degrees(10))
                    .position(x: width * 0.80, y: height * 0.76)
                PorcelainKeyBorderStrip()
                    .stroke(Color.porcelainBlue.opacity(0.12), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                    .frame(width: 128, height: 30)
                    .rotationEffect(.degrees(-8))
                    .position(x: width * 0.80, y: height * 0.34)
                PorcelainKeyBorderStrip()
                    .stroke(Color.porcelainGold.opacity(0.20), style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round))
                    .frame(width: 96, height: 24)
                    .position(x: width * 0.18, y: height * 0.16)
            }
            .allowsHitTesting(false)
        }
    }
}

struct PorcelainMedallion: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.porcelainBlue.opacity(0.14), lineWidth: 2)
            Circle()
                .stroke(Color.porcelainBlue.opacity(0.08), lineWidth: 10)
                .padding(18)
            WaveLine()
                .stroke(Color.porcelainBlue.opacity(0.16), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .frame(width: 96, height: 18)
            WaveLine()
                .stroke(Color.porcelainDeepBlue.opacity(0.10), style: StrokeStyle(lineWidth: 2.0, lineCap: .round))
                .frame(width: 76, height: 16)
                .offset(y: 24)
        }
    }
}

struct PorcelainKeyBorderStrip: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let unit = rect.width / 5
        let top = rect.minY + rect.height * 0.24
        let mid = rect.midY
        let bottom = rect.maxY - rect.height * 0.24

        path.move(to: CGPoint(x: rect.minX, y: top))
        for index in 0..<5 {
            let x = rect.minX + CGFloat(index) * unit
            path.addLine(to: CGPoint(x: x + unit * 0.72, y: top))
            path.addLine(to: CGPoint(x: x + unit * 0.72, y: mid))
            path.addLine(to: CGPoint(x: x + unit * 0.34, y: mid))
            path.addLine(to: CGPoint(x: x + unit * 0.34, y: bottom))
            path.addLine(to: CGPoint(x: x + unit, y: bottom))
        }

        return path
    }
}

struct PorcelainRimOverlay: View {
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.porcelainBlue.opacity(0.30), lineWidth: 1.2)
            RoundedRectangle(cornerRadius: max(0, cornerRadius - 8), style: .continuous)
                .stroke(Color.porcelainBlue.opacity(0.10), lineWidth: 0.8)
                .padding(7)
            VStack {
                HStack {
                    PorcelainKeyBorderStrip()
                        .stroke(Color.porcelainBlue.opacity(0.18), style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
                        .frame(width: 76, height: 18)
                    Spacer()
                    PorcelainKeyBorderStrip()
                        .stroke(Color.porcelainBlue.opacity(0.18), style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
                        .frame(width: 76, height: 18)
                        .rotationEffect(.degrees(180))
                }
                Spacer()
            }
            .padding(14)
        }
    }
}

struct BeachWaveBand: Shape {
    var amplitude: CGFloat = 12
    var phase: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let baseline = rect.minY + amplitude + 2
        path.move(to: CGPoint(x: rect.minX, y: baseline))

        let segments = 64
        for index in 0...segments {
            let progress = CGFloat(index) / CGFloat(segments)
            let x = rect.minX + rect.width * progress
            let angle = (progress + phase) * .pi * 4
            let y = baseline + sin(angle) * amplitude * 0.42 + sin(angle * 0.5) * amplitude * 0.28
            path.addLine(to: CGPoint(x: x, y: y))
        }

        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct BeachWaveDivider: View {
    var color: Color = .beachSeaBlue

    var body: some View {
        BeachWaveLine(amplitude: 5, phase: 0.12)
            .stroke(color.opacity(0.34), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .frame(height: 18)
            .accessibilityHidden(true)
    }
}

struct BeachWaveLine: Shape {
    var amplitude: CGFloat = 8
    var phase: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let baseline = rect.midY
        let segments = 64
        for index in 0...segments {
            let progress = CGFloat(index) / CGFloat(segments)
            let x = rect.minX + rect.width * progress
            let angle = (progress + phase) * .pi * 4
            let y = baseline + sin(angle) * amplitude * 0.42 + sin(angle * 0.5) * amplitude * 0.28
            if index == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        return path
    }
}

struct BeachShellMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.height * 0.50),
            control1: CGPoint(x: rect.width * 0.30, y: rect.height * 0.94),
            control2: CGPoint(x: rect.width * 0.06, y: rect.height * 0.76)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.06),
            control1: CGPoint(x: rect.width * 0.10, y: rect.height * 0.22),
            control2: CGPoint(x: rect.width * 0.32, y: rect.height * 0.03)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX - rect.width * 0.08, y: rect.height * 0.50),
            control1: CGPoint(x: rect.width * 0.68, y: rect.height * 0.03),
            control2: CGPoint(x: rect.width * 0.90, y: rect.height * 0.22)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control1: CGPoint(x: rect.width * 0.94, y: rect.height * 0.76),
            control2: CGPoint(x: rect.width * 0.70, y: rect.height * 0.94)
        )
        path.closeSubpath()
        return path
    }
}

struct BeachStarfishMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) * 0.48
        let inner = outer * 0.38
        let points = 10

        for index in 0..<points {
            let radius = index.isMultiple(of: 2) ? outer : inner
            let angle = -CGFloat.pi / 2 + CGFloat(index) * CGFloat.pi / 5
            let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

struct BeachFootprints: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addEllipse(in: CGRect(x: rect.width * 0.10, y: rect.height * 0.54, width: rect.width * 0.34, height: rect.height * 0.40))
        path.addEllipse(in: CGRect(x: rect.width * 0.52, y: rect.height * 0.08, width: rect.width * 0.34, height: rect.height * 0.40))
        return path
    }
}

struct BeachSectionCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .background(
                LinearGradient(
                    colors: [Color.white.opacity(0.92), Color.beachSand.opacity(0.76)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.88), lineWidth: 1.5)
            }
            .shadow(color: Color.beachSeaBlue.opacity(0.10), radius: 16, x: 0, y: 10)
    }
}

private struct WaveLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midY = rect.midY
        path.move(to: CGPoint(x: rect.minX, y: midY))
        path.addCurve(
            to: CGPoint(x: rect.midX, y: midY),
            control1: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.minY),
            control2: CGPoint(x: rect.minX + rect.width * 0.32, y: rect.maxY)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: midY),
            control1: CGPoint(x: rect.minX + rect.width * 0.68, y: rect.minY),
            control2: CGPoint(x: rect.minX + rect.width * 0.82, y: rect.maxY)
        )
        return path
    }
}

private struct AlbumBackgroundDoodles: View {
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            ZStack {
                Circle()
                    .fill(Color.dopaminePink.opacity(0.13))
                    .frame(width: 160, height: 160)
                    .blur(radius: 28)
                    .position(x: width * 0.88, y: height * 0.12)
                Circle()
                    .fill(Color.dopamineMint.opacity(0.12))
                    .frame(width: 180, height: 180)
                    .blur(radius: 32)
                    .position(x: width * 0.08, y: height * 0.56)
                Capsule()
                    .fill(Color.dopamineYellow.opacity(0.16))
                    .frame(width: 120, height: 34)
                    .rotationEffect(.degrees(-12))
                    .position(x: width * 0.74, y: height * 0.76)
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.46))
                    .position(x: width * 0.12, y: height * 0.18)
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.dopamineBlue.opacity(0.14))
                    .rotationEffect(.degrees(-18))
                    .position(x: width * 0.82, y: height * 0.30)
                Image(systemName: "sparkle")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.dopaminePink.opacity(0.22))
                    .position(x: width * 0.76, y: height * 0.68)
            }
            .allowsHitTesting(false)
        }
    }
}

struct DreamImage: View {
    let path: String?
    let height: CGFloat

    var body: some View {
        GeometryReader { proxy in
            if let image = displayImage {
                imageView(image, in: proxy.size)
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipped()
    }

    private var displayImage: UIImage? {
        if let path, path.hasPrefix("sample:") {
            return UIImage(named: "DemoDream")
        }
        if let path,
           let url = ImageLibrary.imageURL(for: path) {
            return UIImage(contentsOfFile: url.path)
        }
        return nil
    }

    private func imageView(_ image: UIImage, in size: CGSize) -> some View {
        let shouldPreserveFullImage = shouldUseContainedLayout(for: image, in: size)

        return ZStack {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .blur(radius: shouldPreserveFullImage ? 18 : 0)
                .scaleEffect(shouldPreserveFullImage ? 1.08 : 1)
                .opacity(shouldPreserveFullImage ? 0.62 : 1)
                .clipped()

            if shouldPreserveFullImage {
                Color.black.opacity(0.10)
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size.width, height: size.height)
                    .background(Color.black.opacity(0.04))
            }
        }
    }

    private func shouldUseContainedLayout(for image: UIImage, in size: CGSize) -> Bool {
        let imageAspect = max(image.size.width, 1) / max(image.size.height, 1)
        let containerAspect = max(size.width, 1) / max(size.height, 1)
        let aspectDelta = max(imageAspect / max(containerAspect, 0.01), containerAspect / max(imageAspect, 0.01))

        // Photos usually tolerate a gentle crop. Screenshots, posters, long images,
        // and square graphics often contain text or UI, so preserve the full image.
        return imageAspect < 0.72 || imageAspect > 2.05 || aspectDelta > 2.15
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [Color.albumPaper, Color.warmBlush.opacity(0.34), Color.white],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "photo")
                .font(.largeTitle)
                .foregroundStyle(Color.albumGreen.opacity(0.35))
        }
    }
}

struct AlbumCollage: View {
    let paths: [String]

    var body: some View {
        MagazineCollageView(paths: paths, cornerRadius: 0, showCountBadge: true)
    }
}

struct MagazineCollageView: View {
    let paths: [String]
    var cornerRadius: CGFloat = 22
    var showCountBadge = true

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                Color.albumPaper
                if paths.isEmpty {
                    DreamImage(path: nil, height: size.height)
                } else {
                    magazineCollage(in: size)
                }
                LinearGradient(
                    colors: [.clear, .black.opacity(paths.isEmpty ? 0 : 0.18)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                filmGrain
            }
            .overlay(alignment: .bottomTrailing) {
                if showCountBadge && paths.count > 1 {
                    Label("\(paths.count) 张", systemImage: "photo.on.rectangle")
                        .font(.caption.weight(.heavy))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.black.opacity(0.46), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(12)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.72), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.16), radius: 18, y: 10)
            .clipped()
        }
    }

    private var filmGrain: some View {
        ZStack {
            ForEach(0..<7, id: \.self) { index in
                Rectangle()
                    .fill(.white.opacity(index.isMultiple(of: 2) ? 0.07 : 0.035))
                    .frame(height: 1)
                    .offset(y: CGFloat(index * 31) - 94)
            }
        }
        .blendMode(.overlay)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func magazineCollage(in size: CGSize) -> some View {
        let visible = Array(paths.prefix(4))
        switch visible.count {
        case 1:
            DreamImage(path: visible[0], height: size.height)
        case 2:
            ZStack {
                DreamImage(path: visible[0], height: size.height)
                    .frame(width: size.width, height: size.height)
                DreamImage(path: visible[1], height: size.height * 0.48)
                    .frame(width: size.width * 0.46, height: size.height * 0.48)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(.white.opacity(0.9), lineWidth: 5)
                    }
                    .rotationEffect(.degrees(-4))
                    .shadow(color: .black.opacity(0.24), radius: 14, y: 8)
                    .offset(x: size.width * 0.22, y: size.height * 0.18)
            }
        case 3:
            ZStack(alignment: .bottomTrailing) {
                DreamImage(path: visible[0], height: size.height)
                    .frame(width: size.width, height: size.height)
                VStack(spacing: 8) {
                    tile(visible[1], width: size.width * 0.34, height: size.height * 0.24, rotation: 3)
                    tile(visible[2], width: size.width * 0.34, height: size.height * 0.24, rotation: -2)
                }
                .padding(14)
            }
        default:
            ZStack {
                DreamImage(path: visible[0], height: size.height)
                    .frame(width: size.width, height: size.height)
                LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.48)], startPoint: .top, endPoint: .bottom)
                HStack(alignment: .bottom, spacing: 8) {
                    Spacer()
                    tile(visible[1], width: size.width * 0.28, height: size.height * 0.31, rotation: -5)
                    tile(visible[2], width: size.width * 0.28, height: size.height * 0.38, rotation: 3)
                    tile(visible[3], width: size.width * 0.28, height: size.height * 0.31, rotation: -1)
                        .overlay {
                            if paths.count > 4 {
                                ZStack {
                                    Color.black.opacity(0.38)
                                    Text("+\(paths.count - 4)")
                                        .font(.title2.bold())
                                        .foregroundStyle(.white)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }
                }
                .padding(12)
            }
        }
    }

    private func tile(_ path: String, width: CGFloat, height: CGFloat, rotation: Double = 0) -> some View {
        DreamImage(path: path, height: height)
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.white.opacity(0.92), lineWidth: 4)
            }
            .rotationEffect(.degrees(rotation))
            .shadow(color: .black.opacity(0.24), radius: 12, y: 8)
    }
}

struct HomeAlbumCoverView: View {
    let paths: [String]
    var cornerRadius: CGFloat = 20
    var overlayScale: CGFloat = 0.42

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .center) {
                Color.albumPaper

                DreamImage(path: paths.first, height: size.height)
                    .frame(width: size.width, height: size.height)

                let overlays = Array(paths.dropFirst().prefix(2))
                if let secondPath = overlays.first {
                    overlayImage(secondPath, in: size, index: 0, extraCount: 0)
                }
                if overlays.count > 1 {
                    overlayImage(overlays[1], in: size, index: 1, extraCount: max(paths.count - 3, 0))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.74), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    private func overlayImage(_ path: String, in size: CGSize, index: Int, extraCount: Int) -> some View {
        let side = min(size.width, size.height) * overlayScale
        let corner = max(12, side * 0.22)
        let xOffset = index == 0 ? size.width * 0.16 : size.width * 0.29
        let yOffset = index == 0 ? -size.height * 0.13 : size.height * 0.12

        return DreamImage(path: path, height: side)
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(.white.opacity(0.92), lineWidth: max(3, side * 0.06))
            }
            .overlay {
                if extraCount > 0 {
                    ZStack {
                        Color.black.opacity(0.42)
                        Text("+\(extraCount)")
                            .font(.system(size: max(15, side * 0.24), weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                }
            }
            .shadow(color: .black.opacity(0.22), radius: 10, y: 5)
            .frame(width: size.width, height: size.height, alignment: .center)
            .offset(x: xOffset, y: yOffset)
    }
}

struct SharePosterView: View {
    @EnvironmentObject private var store: DreamStore
    let dream: Dream

    private var latestText: String {
        dream.latestLog?.action ?? (dream.visionText.isEmpty ? copy("记录梦想与进展。", "Record dreams and progress.") : dream.visionText)
    }

    private var stageText: String {
        if let stage = dream.milestones.first(where: { !$0.isDone }) {
            return copy("下一步 / \(stage.title)", "Next step / \(stage.title)")
        }
        if let stage = dream.milestones.filter(\.isDone).last {
            return copy("已完成下一步 / \(stage.title)", "Completed step / \(stage.title)")
        }
        return copy("记录梦想与进展。", "Record dreams and progress.")
    }

    private var coverPath: String? {
        dream.imagePaths.first
    }

    private var secondaryImages: [String] {
        Array(dream.imagePaths.dropFirst().prefix(3))
    }

    private var remainingImageCount: Int {
        max(dream.imagePaths.count - 4, 0)
    }

    private var posterTimelineItems: [DreamTimelineItem] {
        Array(dream.timelineItems.prefix(3))
    }

    var body: some View {
        ZStack {
            posterBackground
            VStack(alignment: .leading, spacing: 28) {
                posterHeader
                posterCover
                posterStoryCard
                Spacer(minLength: 0)
                posterFooter
            }
            .padding(.horizontal, 58)
            .padding(.top, 62)
            .padding(.bottom, 54)
        }
    }

    private var posterBackground: some View {
        ZStack {
            Color.albumPaper
            Color.white.opacity(0.12)
            VStack(spacing: 34) {
                ForEach(0..<18, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.albumInk.opacity(0.025))
                        .frame(height: 1)
                }
            }
            .padding(.horizontal, 48)
        }
    }

    private func posterBackgroundGradient(for style: AlbumBackgroundStyle) -> LinearGradient {
        switch style {
        case .morningMistBlue:
            return LinearGradient.albumBackground
        case .rainBlue:
            return LinearGradient(
                colors: [
                    Color(red: 0.925, green: 0.958, blue: 0.985),
                    Color(red: 0.825, green: 0.890, blue: 0.940),
                    Color(red: 0.760, green: 0.840, blue: 0.900)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .porcelainWhite:
            return LinearGradient(
                colors: [
                    Color(red: 0.990, green: 0.995, blue: 1.000),
                    Color(red: 0.950, green: 0.965, blue: 0.980),
                    Color(red: 0.930, green: 0.948, blue: 0.965)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        case .mistPink:
            return LinearGradient(
                colors: [
                    Color(red: 0.995, green: 0.955, blue: 0.965),
                    Color(red: 0.955, green: 0.895, blue: 0.925),
                    Color(red: 0.905, green: 0.865, blue: 0.915)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .lakeBlue:
            return LinearGradient(
                colors: [
                    Color(red: 0.900, green: 0.955, blue: 0.965),
                    Color(red: 0.775, green: 0.885, blue: 0.920),
                    Color(red: 0.675, green: 0.805, blue: 0.865)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var posterHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("DREAM ALBUM")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .tracking(7)
                    .foregroundStyle(Color.albumGreen)
                Text(Date().formatted(.dateTime.year().month().day()))
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.albumGreen.opacity(0.72))
            }
            Spacer()
            Text(copy("\(max(dream.imagePaths.count, 0)) 张画面", "\(max(dream.imagePaths.count, 0)) photos"))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Color.albumGreen)
                .padding(.horizontal, 20)
                .padding(.vertical, 11)
                .background(Color.white.opacity(0.72), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(Color.albumInk.opacity(0.08), lineWidth: 1)
                }
        }
    }

    private var posterCover: some View {
        ZStack(alignment: .bottomLeading) {
            DreamImage(path: coverPath, height: 820)
                .frame(height: 820)
            LinearGradient(
                colors: [.clear, .black.opacity(0.18), .black.opacity(0.78)],
                startPoint: .top,
                endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: 18) {
                Text("MY DREAM")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .tracking(6)
                    .foregroundStyle(.white.opacity(0.7))
                Text(dream.title)
                    .font(.system(size: 92, weight: .black, design: .serif))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.62)
                Text(copy("\(dream.evidenceCount) 条记录  /  \(dream.imagePaths.count) 张画面", "\(dream.evidenceCount) records  /  \(dream.imagePaths.count) photos"))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.86))
            }
            .padding(44)

            if !secondaryImages.isEmpty {
                HStack(spacing: 12) {
                    ForEach(Array(secondaryImages.enumerated()), id: \.offset) { index, path in
                        DreamImage(path: path, height: 118)
                            .frame(width: 118, height: 118)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay {
                                if index == secondaryImages.count - 1, remainingImageCount > 0 {
                                    ZStack {
                                        Color.black.opacity(0.42)
                                        Text("+\(remainingImageCount)")
                                            .font(.system(size: 34, weight: .black, design: .rounded))
                                            .foregroundStyle(.white)
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                }
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(.white.opacity(0.92), lineWidth: 4)
                            }
                    }
                }
                .padding(18)
                .background(.black.opacity(0.20), in: Capsule())
                .padding(34)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 42, style: .continuous))
        .shadow(color: .black.opacity(0.13), radius: 28, y: 16)
    }

    private var posterStoryCard: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(copy("最新成长记录", "Latest Record"))
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(Color.albumGreen.opacity(0.78))
                    Text(latestText)
                        .font(.system(size: 50, weight: .semibold, design: .serif))
                        .lineSpacing(8)
                        .foregroundStyle(Color.albumInk)
                        .lineLimit(3)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 18) {
                    posterMetric("\(dream.evidenceCount)", copy("成长记录", "Records"))
                    posterMetric("\(dream.completedStageCount)", copy("完成下一步", "Steps"))
                }
            }

            if !dream.visionText.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(copy("梦想描述", "Vision"))
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle(Color.albumGreen.opacity(0.78))
                    Text(dream.visionText)
                        .font(.system(size: 32, weight: .semibold, design: .serif))
                        .foregroundStyle(Color.albumInk)
                        .lineLimit(2)
                }
            }

            if !posterTimelineItems.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    Text(copy("成长足迹", "Journey"))
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundStyle(Color.albumGreen.opacity(0.78))
                    VStack(alignment: .leading, spacing: 13) {
                        ForEach(posterTimelineItems) { item in
                            posterTimelineRow(item)
                        }
                    }
                }
                .padding(.top, 2)
            }

            Text(stageText)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(Color.albumGreen)
                .padding(.horizontal, 24)
                .padding(.vertical, 13)
                .background(Color.albumGreen.opacity(0.08), in: Capsule())
        }
        .padding(42)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 34, style: .continuous))
    }

    private var posterFooter: some View {
        HStack(alignment: .bottom) {
            Text(copy("梦想相册", "Dream Album"))
                .font(.system(size: 34, weight: .black, design: .serif))
            Spacer()
            Text(copy("记录梦想与进展。", "Record dreams and progress."))
                .font(.system(size: 28, weight: .bold, design: .rounded))
        }
        .foregroundStyle(Color.albumGreen)
    }

    private func posterMetric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(value)
                .font(.system(size: 48, weight: .black, design: .rounded))
                .foregroundStyle(Color.albumGreen)
            Text(label)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(width: 138, alignment: .trailing)
    }

    private func posterTimelineRow(_ item: DreamTimelineItem) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Circle()
                .fill(timelineDotColor(item))
                .frame(width: 12, height: 12)
                .padding(.top, 9)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.sortDate.formatted(.dateTime.month().day()))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                Text(timelineTitle(item))
                    .font(.system(size: 24, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.albumInk)
                    .lineLimit(1)
            }
        }
    }

    private func timelineTitle(_ item: DreamTimelineItem) -> String {
        switch item {
        case .log(let log):
            return log.action
        case .stage(let stage):
            return copy("完成下一步：\(stage.title)", "Completed step: \(stage.title)")
        }
    }

    private func copy(_ chinese: String, _ english: String) -> String {
        AlbumCopy.pick(store.appLanguage, chinese, english)
    }

    private func timelineDotColor(_ item: DreamTimelineItem) -> Color {
        switch item {
        case .log:
            return Color.albumGreen
        case .stage:
            return Color.softGold
        }
    }
}

struct MoodboardCollageView: View {
    let paths: [String]
    var cornerRadius: CGFloat = 28
    var compact = false

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.78),
                                Color(red: 0.90, green: 0.96, blue: 0.99).opacity(0.72),
                                Color(red: 1.00, green: 0.92, blue: 0.72).opacity(0.24)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Circle()
                    .fill(Color(red: 1.0, green: 0.46, blue: 0.56).opacity(0.16))
                    .frame(width: size.width * 0.42)
                    .blur(radius: 20)
                    .offset(x: size.width * 0.36, y: -size.height * 0.26)

                Circle()
                    .fill(Color(red: 0.44, green: 0.42, blue: 0.95).opacity(0.13))
                    .frame(width: size.width * 0.36)
                    .blur(radius: 18)
                    .offset(x: -size.width * 0.34, y: size.height * 0.24)

                if paths.isEmpty {
                    emptyPrint(in: size)
                } else {
                    collagePrints(in: size)
                }

                CollageTape(color: Color.softGold.opacity(0.70), rotation: -8)
                    .offset(x: -size.width * 0.28, y: -size.height * 0.34)

                if !compact {
                    CollageTape(color: Color(red: 1.0, green: 0.72, blue: 0.76).opacity(0.48), rotation: 7)
                        .offset(x: size.width * 0.30, y: -size.height * 0.30)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.78), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: Color.albumInk.opacity(0.10), radius: 18, y: 10)
        }
    }

    @ViewBuilder
    private func collagePrints(in size: CGSize) -> some View {
        let visible = Array(paths.prefix(3))
        let extra = max(paths.count - 3, 0)

        photoPrint(path: visible[0], radius: compact ? 18 : 24)
            .frame(width: compact ? size.width * 0.86 : size.width * 0.70, height: compact ? size.height * 0.78 : size.height * 0.72)
            .rotationEffect(.degrees(compact ? -2 : -4))
            .offset(x: compact ? -size.width * 0.03 : -size.width * 0.10, y: compact ? size.height * 0.02 : size.height * 0.04)

        if visible.count > 1 {
            photoPrint(path: visible[1], radius: compact ? 14 : 18)
                .frame(width: compact ? size.width * 0.36 : size.width * 0.34, height: compact ? size.height * 0.34 : size.height * 0.31)
                .rotationEffect(.degrees(compact ? 5 : 6))
                .offset(x: size.width * 0.27, y: compact ? -size.height * 0.16 : -size.height * 0.22)
        } else if !compact {
            notePatch(text: "DREAM")
                .offset(x: size.width * 0.27, y: -size.height * 0.18)
        }

        if visible.count > 2 {
            photoPrint(path: visible[2], radius: compact ? 14 : 18)
                .frame(width: compact ? size.width * 0.34 : size.width * 0.30, height: compact ? size.height * 0.30 : size.height * 0.28)
                .rotationEffect(.degrees(-5))
                .overlay {
                    if extra > 0 {
                        RoundedRectangle(cornerRadius: compact ? 14 : 18, style: .continuous)
                            .fill(.black.opacity(0.34))
                        Text("+\(extra)")
                            .font(.system(size: compact ? 20 : 26, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }
                .offset(x: size.width * 0.31, y: compact ? size.height * 0.18 : size.height * 0.18)
        }
    }

    private func photoPrint(path: String?, radius: CGFloat) -> some View {
        GeometryReader { proxy in
            DreamImage(path: path, height: max(proxy.size.height - 12, 1))
                .frame(width: max(proxy.size.width - 12, 1), height: max(proxy.size.height - 12, 1))
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .padding(6)
                .background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: radius + 6, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: radius + 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: radius + 6, style: .continuous)
                        .stroke(.white.opacity(0.92), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.16), radius: 12, x: 0, y: 7)
            }
    }

    private func emptyPrint(in size: CGSize) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: compact ? 26 : 34, weight: .bold))
            Text("DREAM")
                .font(.caption.weight(.black))
                .tracking(3)
        }
        .foregroundStyle(Color.albumGreen.opacity(0.64))
        .frame(width: size.width * 0.64, height: size.height * 0.58)
        .background(.white.opacity(0.74), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .rotationEffect(.degrees(-3))
    }

    private func notePatch(text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.black))
            .tracking(2)
            .foregroundStyle(Color.albumInk.opacity(0.52))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.softGold.opacity(0.58), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .rotationEffect(.degrees(8))
    }
}

struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct CollageSticker: View {
    let text: String
    var symbol: String?
    var tint: Color = Color.albumGreen
    var fill: Color = Color.white.opacity(0.86)

    var body: some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.caption.weight(.black))
            }
            Text(text)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(fill, in: Capsule())
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.72), lineWidth: 1)
        }
        .shadow(color: tint.opacity(0.14), radius: 10, x: 0, y: 5)
    }
}

struct CollageTape: View {
    var color: Color = Color.softGold.opacity(0.74)
    var rotation: Double = -6

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(color)
            .frame(width: 74, height: 22)
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(.white.opacity(0.42), lineWidth: 1)
            }
            .rotationEffect(.degrees(rotation))
            .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
            .blendMode(.plusLighter)
    }
}

struct CollageSectionTitle: View {
    let title: String
    var subtitle: String?
    var tint: Color = Color.albumGreen

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            Text(title)
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundStyle(Color.albumInk)
            Spacer()
            if let subtitle {
                Text(subtitle)
                    .font(.caption.weight(.black))
                    .foregroundStyle(tint.opacity(0.72))
            }
        }
    }
}

struct CollageCardBackground: ViewModifier {
    var cornerRadius: CGFloat = 24
    var opacity: Double = 0.72

    func body(content: Content) -> some View {
        content
            .background(.white.opacity(opacity), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.62), lineWidth: 1)
            }
            .shadow(color: Color.albumInk.opacity(0.07), radius: 18, x: 0, y: 10)
    }
}

extension View {
    func collageCard(cornerRadius: CGFloat = 24, opacity: Double = 0.72) -> some View {
        modifier(CollageCardBackground(cornerRadius: cornerRadius, opacity: opacity))
    }
}

struct DreamTitleEditorSheet: View {
    @EnvironmentObject private var store: DreamStore
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    let onSave: (String) -> Void

    init(title: String, onSave: @escaping (String) -> Void) {
        _title = State(initialValue: title)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(copy("相册名称", "Album Name")) {
                    TextField(copy("比如：第一次马拉松 / 学会游泳", "e.g. First marathon / Learn to swim"), text: $title)
                        .onChange(of: title) { _, newValue in
                            if newValue.count > 12 {
                                title = String(newValue.prefix(12))
                            }
                        }
                    Text("\(title.count)/12")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(LibraryStyle.background)
            .navigationTitle(copy("修改名称", "Rename Album"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(copy("取消", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(copy("保存", "Save")) {
                        onSave(title)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func copy(_ chinese: String, _ english: String) -> String {
        AlbumCopy.pick(store.appLanguage, chinese, english)
    }
}

struct CompletionBurstView: View {
    let fallbackColor: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(fallbackColor.opacity(0.16))
            Image(systemName: "checkmark")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(fallbackColor)
            LottiePlaybackView(name: "completion_pulse")
                .allowsHitTesting(false)
        }
        .frame(width: 92, height: 92)
        .accessibilityHidden(true)
    }
}

#if canImport(Lottie)
private struct LottiePlaybackView: UIViewRepresentable {
    let name: String

    func makeUIView(context: Context) -> LottieAnimationView {
        let view = LottieAnimationView(name: name)
        view.contentMode = .scaleAspectFit
        view.loopMode = .playOnce
        view.backgroundBehavior = .pauseAndRestore
        view.play()
        return view
    }

    func updateUIView(_ uiView: LottieAnimationView, context: Context) {
        if !uiView.isAnimationPlaying {
            uiView.play()
        }
    }
}
#else
private struct LottiePlaybackView: View {
    let name: String

    var body: some View {
        EmptyView()
    }
}
#endif

struct MoodChartSection: View {
    @EnvironmentObject private var store: DreamStore
    let scores: [(date: Date, score: Int)]
    private func c(_ zh: String, _ en: String) -> String { AlbumCopy.pick(store.appLanguage, zh, en) }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(c("与梦想同行的心情", "Mood along the way")).font(.title3.bold())
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .trailing) {
                    Text(c("向上", "Up")); Spacer(); Text(c("平稳", "Steady")); Spacer(); Text(c("低谷", "Low"))
                }.font(.caption2).foregroundStyle(.secondary).frame(height: 180)
                ScrollView(.horizontal, showsIndicators: false) {
                    MoodLineChart(scores: scores, tint: LibraryStyle.mint)
                        .frame(width: max(CGFloat(scores.count) * 58, 260), height: 180)
                }
            }
        }.padding(18).background(LibraryStyle.surface, in: RoundedRectangle(cornerRadius: 22))
    }
}

struct MoodLineChart: View {
    let scores: [(date: Date, score: Int)]
    let tint: Color

    var body: some View {
        ChartCanvas(scores: scores, tint: tint)
            .overlay(alignment: .bottom) {
                HStack {
                    ForEach(Array(scores.enumerated()), id: \.offset) { _, item in
                        Text(item.date.formatted(.dateTime.month().day()))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 52)
                    }
                }
                .frame(maxWidth: .infinity)
            }
    }
}

private struct ChartCanvas: View {
    let scores: [(date: Date, score: Int)]
    let tint: Color

    var body: some View {
        Canvas { context, size in
            let top: CGFloat = 18
            let bottom: CGFloat = 34
            let left: CGFloat = 16
            let right: CGFloat = 16
            let plotHeight = size.height - top - bottom
            let plotWidth = size.width - left - right
            let values = scores.map(\.score)
            let maxValue = max(values.max() ?? 1, 1)
            let minValue = min(values.min() ?? -1, -1)
            let range = CGFloat(maxValue - minValue)

            for line in 0...2 {
                let y = top + plotHeight * CGFloat(line) / 2
                var grid = Path()
                grid.move(to: CGPoint(x: left, y: y))
                grid.addLine(to: CGPoint(x: size.width - right, y: y))
                context.stroke(grid, with: .color(tint.opacity(0.13)), lineWidth: 1)
            }

            guard scores.count > 1 else { return }

            func point(_ index: Int, _ value: Int) -> CGPoint {
                let x = left + plotWidth * CGFloat(index) / CGFloat(max(scores.count - 1, 1))
                let normalized = CGFloat(value - minValue) / max(range, 1)
                let y = top + plotHeight * (1 - normalized)
                return CGPoint(x: x, y: y)
            }

            var path = Path()
            path.move(to: point(0, scores[0].score))
            for index in scores.indices.dropFirst() {
                path.addLine(to: point(index, scores[index].score))
            }
            context.stroke(path, with: .color(tint), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

            for index in scores.indices {
                let p = point(index, scores[index].score)
                context.fill(Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)), with: .color(.white))
                context.stroke(Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)), with: .color(tint), lineWidth: 2)
            }
        }
    }
}

extension Color {
    static let albumGreen = Color(red: 0.18, green: 0.29, blue: 0.36)
    static let softGold = Color(red: 0.72, green: 0.55, blue: 0.32)
    static let warmBlush = Color(red: 0.74, green: 0.84, blue: 0.90)
    static let albumPaper = Color(red: 0.933, green: 0.957, blue: 0.973)
    static let albumInk = Color(red: 0.08, green: 0.13, blue: 0.17)
    static let filmBlack = Color(red: 0.06, green: 0.08, blue: 0.10)
    static let dopamineBlue = Color(red: 0.12, green: 0.47, blue: 1.00)
    static let dopaminePink = Color(red: 1.00, green: 0.35, blue: 0.54)
    static let dopamineYellow = Color(red: 1.00, green: 0.82, blue: 0.18)
    static let dopamineMint = Color(red: 0.28, green: 0.86, blue: 0.64)
    static let beachSky = Color(red: 0.88, green: 0.97, blue: 1.00)
    static let beachSand = Color(red: 1.00, green: 0.94, blue: 0.82)
    static let beachCoral = Color(red: 1.00, green: 0.46, blue: 0.34)
    static let beachShellPink = Color(red: 1.00, green: 0.72, blue: 0.78)
    static let beachSeaBlue = Color(red: 0.05, green: 0.58, blue: 0.82)
    static let beachMint = Color(red: 0.44, green: 0.88, blue: 0.76)
    static let porcelainWhite = Color(red: 0.985, green: 0.992, blue: 1.000)
    static let porcelainMist = Color(red: 0.910, green: 0.955, blue: 0.985)
    static let porcelainBlue = Color(red: 0.10, green: 0.38, blue: 0.68)
    static let porcelainDeepBlue = Color(red: 0.04, green: 0.17, blue: 0.36)
    static let porcelainGold = Color(red: 0.70, green: 0.55, blue: 0.30)
}

extension LinearGradient {
    static let albumBackground = LinearGradient(
        colors: [
            Color(red: 0.940, green: 0.985, blue: 1.000),
            Color(red: 0.835, green: 0.945, blue: 0.985),
            Color(red: 0.735, green: 0.885, blue: 0.945)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
