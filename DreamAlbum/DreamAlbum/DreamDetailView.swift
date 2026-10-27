import PhotosUI
import SwiftUI
import UIKit

private struct ImagePreview: Identifiable {
    let path: String
    var id: String { path }
}

private struct FullScreenImagePreview: View {
    let path: String

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.ignoresSafeArea()

                if let image = displayImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "photo")
                            .font(.largeTitle)
                        Text("Image cannot be previewed")
                            .font(.headline)
                    }
                    .foregroundStyle(.white.opacity(0.82))
                }
            }
        }
    }

    private var displayImage: UIImage? {
        if path.hasPrefix("sample:") {
            return UIImage(named: "DemoDream")
        }
        guard let url = ImageLibrary.imageURL(for: path) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}

struct DreamDetailView: View {
    @EnvironmentObject private var store: DreamStore
    @Environment(\.dismiss) private var dismiss
    @State private var dream: Dream
    @State private var recordText = ""
    @State private var selectedMood: DreamMood?
    @State private var recordDate = Date()
    @State private var selectedRecordPhotos: [PhotosPickerItem] = []
    @State private var recordImagePaths: [String] = []
    @State private var selectedAlbumPhotos: [PhotosPickerItem] = []
    @State private var isShowingAlbumCamera = false
    @State private var isShowingRecordCamera = false
    @State private var previewImage: ImagePreview?
    @State private var editingLog: DreamLog?
    @State private var editingStage: DreamStage?
    @State private var isEditingTitle = false
    @State private var isEditingVision = false
    @State private var posterPreviewImage: UIImage?
    @State private var activityShareImage: UIImage?
    @State private var shareError = false
    @State private var showCompletion = false
    @State private var completionMessage = "已保存"
    @State private var newStageTitle = ""
    @State private var newStageHasTargetDate = false
    @State private var newStageTargetDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @FocusState private var isRecordFocused: Bool

    init(dream: Dream) {
        _dream = State(initialValue: dream)
    }

    // The live app has one appearance; legacy theme settings still decode.
    private var isBeachStyle: Bool { false }
    private var detailSectionFill: AnyShapeStyle { AnyShapeStyle(LibraryStyle.surface) }
    private var detailActionTint: Color { LibraryStyle.mint }

    var body: some View {
        ZStack {
            AlbumBackground()
            ScrollView {
                detailContent
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
            }
        }
        .navigationTitle(dream.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        isEditingTitle = true
                    } label: {
                        Label(copy("修改名称", "Rename album"), systemImage: "pencil")
                    }

                    Button {
                        shareAlbum()
                    } label: {
                        Label(copy("分享相册", "Share album"), systemImage: "square.and.arrow.up")
                    }

                    Button {
                        store.archive(dream)
                        dismiss()
                    } label: {
                        Label(copy("归档梦想", "Archive dream"), systemImage: "archivebox")
                    }

                    Button(role: .destructive) {
                        store.delete(dream)
                        dismiss()
                    } label: {
                        Label(copy("删除梦想", "Delete dream"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel(copy("相册操作", "Album actions"))
                .accessibilityIdentifier("dream.actions")
            }
        }
        .onChange(of: store.dreams) { _, dreams in
            if let latest = dreams.first(where: { $0.id == dream.id }) {
                dream = latest
            }
        }
        .overlay(alignment: .top) {
            if showCompletion {
                HStack(spacing: 10) {
                    CompletionBurstView(fallbackColor: Color.albumGreen)
                        .frame(width: 42, height: 42)
                    Text(completionMessage)
                        .font(.headline)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.top, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .sheet(item: $previewImage) { preview in
            FullScreenImagePreview(path: preview.path)
                .ignoresSafeArea()
                .presentationBackground(.black)
            .overlay(alignment: .topTrailing) {
                Button {
                    previewImage = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white)
                    .padding(.top, 12)
                    .padding(.trailing, 18)
                }
            }
        }
        .sheet(item: $editingLog) { log in
            DreamLogEditorSheet(log: log) { updatedLog in
                updateLog(updatedLog)
                editingLog = nil
            }
        }
        .sheet(item: $editingStage) { stage in
            DreamStageEditorSheet(stage: stage) { updatedStage in
                updateStage(updatedStage)
                editingStage = nil
            }
        }
        .sheet(isPresented: $isEditingTitle) {
            DreamTitleEditorSheet(title: dream.title) { updatedTitle in
                updateDreamTitle(updatedTitle)
                isEditingTitle = false
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $isEditingVision) {
            DreamVisionEditorSheet(text: dream.visionText) { updatedText in
                updateVisionText(updatedText)
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $isShowingAlbumCamera) {
            CameraCaptureView { image in
                saveCapturedAlbumImage(image)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $isShowingRecordCamera) {
            CameraCaptureView { image in
                saveCapturedRecordImage(image)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: Binding(
            get: { posterPreviewImage != nil },
            set: { if !$0 { posterPreviewImage = nil } }
        )) {
            if let posterPreviewImage {
                PosterPreviewSheet(image: posterPreviewImage) {
                    let image = posterPreviewImage
                    self.posterPreviewImage = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        activityShareImage = image
                    }
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { activityShareImage != nil },
            set: { if !$0 { activityShareImage = nil } }
        )) {
            if let activityShareImage {
                ActivityShareSheet(items: [activityShareImage])
                    .ignoresSafeArea()
            }
        }
        .alert(copy("暂时无法生成分享图", "Unable to create share image"), isPresented: $shareError) {
            Button(copy("知道了", "OK"), role: .cancel) {}
        } message: {
            Text(copy("可以稍后重试，或先减少图片数量再生成。", "Try again later, or use fewer photos before generating it."))
        }

    }

    @ViewBuilder
    private var detailContent: some View {
        defaultDetailContent
    }

    private var defaultDetailContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            albumCarousel
            visionSection
            albumGallerySection

            if dream.isArchived {
                archivedBanner
            }

            if !dream.isArchived {
                dailyRecordSection
            }

            if store.isMoodChartEnabled && !dream.moodScores.isEmpty {
                MoodChartSection(scores: dream.moodScores)
            }

            stageSection
            growthFootprintSection
        }
    }

    private var collageDetailContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            collageHero
            collageVisionSection
            collageGallerySection

            if dream.isArchived {
                archivedBanner
            }

            if !dream.isArchived {
                dailyRecordSection
            }

            if store.isMoodChartEnabled && !dream.moodScores.isEmpty {
                MoodChartSection(scores: dream.moodScores)
            }

            stageSection
            growthFootprintSection
        }
        .padding(.top, 12)
    }

    private var beachDetailContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            beachHero
            beachVisionSection
            beachGallerySection

            if dream.isArchived {
                archivedBanner
            }

            if !dream.isArchived {
                dailyRecordSection
            }

            if store.isMoodChartEnabled && !dream.moodScores.isEmpty {
                MoodChartSection(scores: dream.moodScores)
            }

            stageSection
            growthFootprintSection
        }
        .padding(.top, 12)
    }

    private var porcelainDetailContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            porcelainHero
            porcelainVisionSection
            porcelainGallerySection

            if dream.isArchived {
                archivedBanner
            }

            if !dream.isArchived {
                dailyRecordSection
            }

            if store.isMoodChartEnabled && !dream.moodScores.isEmpty {
                MoodChartSection(scores: dream.moodScores)
            }

            stageSection
            growthFootprintSection
        }
        .padding(.top, 12)
    }

    private var albumCarousel: some View {
        Group {
            if dream.imagePaths.isEmpty {
                DreamImage(path: nil, height: 330)
                    .overlay(alignment: .bottomLeading) {
                        albumTitleOverlay(isEmpty: true)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .padding(.horizontal, 2)
            } else if dream.imagePaths.count == 1, let path = dream.imagePaths.first {
                DreamImage(path: path, height: 330)
                    .overlay(alignment: .bottomLeading) {
                        albumTitleOverlay(isEmpty: false)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .padding(.horizontal, 2)
            } else {
                TabView {
                    ForEach(Array(dream.imagePaths.enumerated()), id: \.offset) { index, path in
                        DreamImage(path: path, height: 330)
                            .overlay(alignment: .bottomLeading) {
                                albumTitleOverlay(isEmpty: false)
                            }
                            .overlay(alignment: .topTrailing) {
                                if dream.imagePaths.count > 1 {
                                    Text("\(index + 1) / \(dream.imagePaths.count)")
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(.black.opacity(0.28), in: Capsule())
                                        .foregroundStyle(.white)
                                        .padding(14)
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .padding(.horizontal, 2)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: dream.imagePaths.count > 1 ? .automatic : .never))
            }
        }
        .frame(height: 350)
        .padding(.top, 12)
    }

    private func albumTitleOverlay(isEmpty: Bool) -> some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                Text(isEmpty ? copy("添加画面", "Add Photo") : copy("梦想相册", "Dream Album"))
                    .font(.caption.weight(.black))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.68))
                Text(dream.title)
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                Text(isEmpty ? copy("给梦想添一张画面", "Add a photo to your dream") : (dream.visionText.isEmpty ? copy("让梦想描述更清楚", "Make the vision clearer") : dream.visionText))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(2)
            }
            .padding(.horizontal, 20)
            .padding(.top, 48)
            .padding(.bottom, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.78)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    private var collageHero: some View {
        themedHero(
            cornerRadius: 32,
            countTint: Color.albumInk,
            styleTitle: nil,
            styleSymbol: nil,
            styleTint: Color.albumGreen,
            fallbackVision: copy("把梦想描述变清楚", "Make the vision clearer"),
            buttonColors: [Color.dopamineBlue, Color(red: 0.05, green: 0.62, blue: 1.0)]
        )
        .overlay {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(.white.opacity(0.78), lineWidth: 3)
        }
        .shadow(color: Color.dopamineBlue.opacity(0.16), radius: 24, x: 0, y: 14)
    }

    private var beachHero: some View {
        themedHero(
            cornerRadius: 32,
            countTint: Color.beachSeaBlue,
            styleTitle: nil,
            styleSymbol: nil,
            styleTint: Color.beachCoral,
            fallbackVision: copy("让梦想变具体，让未来在进行时", "Make dreams specific. Keep the future in motion."),
            buttonColors: [Color.beachCoral, Color(red: 1.00, green: 0.56, blue: 0.32)]
        )
        .padding(9)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.96), Color.beachSand.opacity(0.90)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 38, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 38, style: .continuous)
                .stroke(.white.opacity(0.92), lineWidth: 1.5)
        }
        .background(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 38, style: .continuous)
                .fill(Color.beachShellPink.opacity(0.24))
                .rotationEffect(.degrees(2.2))
                .offset(x: 5, y: 8)
        }
        .shadow(color: Color.beachSeaBlue.opacity(0.16), radius: 24, x: 0, y: 14)
    }

    private var beachVisionSection: some View {
        BeachSectionCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(copy("梦想描述", "Vision"), systemImage: "sparkles")
                        .font(.headline.weight(.black))
                        .foregroundStyle(Color.beachSeaBlue)
                    Spacer()
                    if !dream.isArchived {
                        Menu {
                            Button { isEditingVision = true } label: {
                                Label(dream.visionText.isEmpty ? copy("填写", "Add") : copy("编辑", "Edit"), systemImage: "pencil")
                            }
                            if !dream.visionText.isEmpty {
                                Button(role: .destructive) { updateVisionText("") } label: {
                                    Label(copy("删除", "Delete"), systemImage: "trash")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.headline)
                                .foregroundStyle(Color.albumInk.opacity(0.62))
                                .frame(width: 36, height: 36)
                                .background(.white.opacity(0.76), in: Circle())
                        }
                    }
                }
                BeachWaveDivider(color: .beachSeaBlue)
                Text(dream.visionText.isEmpty ? copy("暂无描述。", "No description.") : dream.visionText)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.albumInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var beachGallerySection: some View {
        BeachSectionCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label(copy("全部画面", "All Photos"), systemImage: "photo.stack")
                        .font(.headline.weight(.black))
                        .foregroundStyle(Color.albumInk)
                    Text(dream.imagePaths.isEmpty ? copy("0 张", "0 photos") : copy("\(dream.imagePaths.count) 张", "\(dream.imagePaths.count) photos"))
                        .font(.caption.weight(.black))
                        .foregroundStyle(Color.beachSeaBlue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.beachSky.opacity(0.74), in: Capsule())
                    Spacer()
                    if !dream.isArchived {
                        PhotosPicker(selection: $selectedAlbumPhotos, matching: .images) {
                            Image(systemName: "plus")
                                .font(.headline.weight(.black))
                                .frame(width: 42, height: 42)
                                .background(Color.beachCoral, in: Circle())
                                .foregroundStyle(.white)
                        }
                        .onChange(of: selectedAlbumPhotos) { _, items in
                            Task { await importAlbumImages(from: items) }
                        }
                    }
                }

                BeachWaveDivider(color: .beachSeaBlue)

                if dream.imagePaths.isEmpty {
                    Label(copy("先添加一张让你心动的画面", "Add a photo that inspires you"), systemImage: "photo")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.beachSeaBlue)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.beachSky.opacity(0.74), in: Capsule())
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Array(dream.imagePaths.enumerated()), id: \.element) { index, path in
                                Button {
                                    previewImage = ImagePreview(path: path)
                                } label: {
                                    DreamImage(path: path, height: 116)
                                        .frame(width: index == 0 ? 150 : 116, height: 116)
                                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                        .overlay(alignment: .topLeading) {
                                            if index == 0 {
                                                Image(systemName: "star.fill")
                                                    .font(.caption.weight(.black))
                                                    .padding(8)
                                                    .background(Color.beachCoral.opacity(0.94), in: Circle())
                                                    .foregroundStyle(.white)
                                                    .padding(7)
                                            }
                                        }
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                .stroke(.white.opacity(0.96), lineWidth: 3)
                                        }
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    if !dream.isArchived {
                                        Button { setCover(path) } label: {
                                            Label(copy("设为封面", "Set as cover"), systemImage: "star")
                                        }
                                        Button(role: .destructive) { deleteAlbumImage(path) } label: {
                                            Label(copy("删除画面", "Delete photo"), systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 2)
                    }
                }
            }
        }
    }

    private var porcelainHero: some View {
        themedHero(
            cornerRadius: 30,
            countTint: Color.porcelainBlue,
            styleTitle: copy("青花相册页", "Porcelain Album"),
            styleSymbol: "seal.fill",
            styleTint: Color.porcelainDeepBlue,
            fallbackVision: copy("让梦想变具体，让未来在进行时", "Make dreams specific. Keep the future in motion."),
            buttonColors: [Color.porcelainBlue, Color.porcelainDeepBlue]
        )
        .padding(8)
        .background(Color.porcelainWhite.opacity(0.90), in: RoundedRectangle(cornerRadius: 38, style: .continuous))
        .overlay {
            PorcelainRimOverlay(cornerRadius: 38)
        }
        .shadow(color: Color.porcelainBlue.opacity(0.14), radius: 24, x: 0, y: 14)
    }

    private func themedHero(
        cornerRadius: CGFloat,
        countTint: Color,
        styleTitle: String?,
        styleSymbol: String?,
        styleTint: Color,
        fallbackVision: String,
        buttonColors: [Color]
    ) -> some View {
        let paths = dream.imagePaths.isEmpty ? [String?](arrayLiteral: nil) : dream.imagePaths.map { Optional($0) }

        return Group {
            if paths.count > 1 {
                TabView {
                    ForEach(Array(paths.enumerated()), id: \.offset) { index, path in
                        themedHeroSlide(
                            path: path,
                            index: index,
                            total: paths.count,
                            cornerRadius: cornerRadius,
                            countTint: countTint,
                            styleTitle: styleTitle,
                            styleSymbol: styleSymbol,
                            styleTint: styleTint,
                            fallbackVision: fallbackVision,
                            buttonColors: buttonColors
                        )
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
            } else {
                themedHeroSlide(
                    path: paths.first ?? nil,
                    index: 0,
                    total: paths.count,
                    cornerRadius: cornerRadius,
                    countTint: countTint,
                    styleTitle: styleTitle,
                    styleSymbol: styleSymbol,
                    styleTint: styleTint,
                    fallbackVision: fallbackVision,
                    buttonColors: buttonColors
                )
            }
        }
        .frame(height: 330)
    }

    private func themedHeroSlide(
        path: String?,
        index: Int,
        total: Int,
        cornerRadius: CGFloat,
        countTint: Color,
        styleTitle: String?,
        styleSymbol: String?,
        styleTint: Color,
        fallbackVision: String,
        buttonColors: [Color]
    ) -> some View {
        ZStack(alignment: .bottomLeading) {
            DreamImage(path: path, height: 330)
                .frame(height: 330)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

            LinearGradient(
                colors: [.clear, .black.opacity(0.16), .black.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(copy("\(dream.imagePaths.count) 张画面", "\(dream.imagePaths.count) photos"), systemImage: "photo")
                        .font(.caption.weight(.black))
                        .foregroundStyle(countTint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.92), in: Capsule())
                    Spacer()
                    if let styleTitle, let styleSymbol {
                        Label(styleTitle, systemImage: styleSymbol)
                            .font(.caption.weight(.black))
                            .foregroundStyle(styleTint)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.white.opacity(0.86), in: Capsule())
                    } else if total > 1 {
                        Text("\(index + 1) / \(total)")
                            .font(.caption.weight(.black))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.black.opacity(0.28), in: Capsule())
                    }
                }
                Spacer()
                Text(dream.title)
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.74)
                Text(dream.visionText.isEmpty ? fallbackVision : dream.visionText)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(2)
                if !dream.isArchived {
                    Label(copy("添加记录", "Add record"), systemImage: "plus")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .background(
                            LinearGradient(colors: buttonColors, startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: Capsule()
                        )
                        .padding(.top, 2)
                }
            }
            .padding(20)
        }
        .frame(height: 330)
    }

    private var porcelainVisionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(copy("梦想描述", "Vision"), systemImage: "scroll.fill")
                    .font(.headline.weight(.black))
                    .foregroundStyle(Color.porcelainBlue)
                Spacer()
                if !dream.isArchived {
                    Menu {
                        Button { isEditingVision = true } label: {
                            Label(dream.visionText.isEmpty ? copy("填写", "Add") : copy("编辑", "Edit"), systemImage: "pencil")
                        }
                        if !dream.visionText.isEmpty {
                            Button(role: .destructive) { updateVisionText("") } label: {
                                Label(copy("删除", "Delete"), systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.headline)
                            .foregroundStyle(Color.porcelainDeepBlue.opacity(0.62))
                            .frame(width: 36, height: 36)
                            .background(.white.opacity(0.76), in: Circle())
                    }
                }
            }
            Text(dream.visionText.isEmpty ? copy("暂无描述。", "No description.") : dream.visionText)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.porcelainDeepBlue)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            PorcelainRimOverlay(cornerRadius: 26)
        }
    }

    private var porcelainGallerySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(copy("全部画面", "All Photos"), systemImage: "photo.stack")
                    .font(.headline.weight(.black))
                    .foregroundStyle(Color.porcelainDeepBlue)
                Text(dream.imagePaths.isEmpty ? copy("0 张", "0 photos") : copy("\(dream.imagePaths.count) 张", "\(dream.imagePaths.count) photos"))
                    .font(.caption.weight(.black))
                    .foregroundStyle(Color.porcelainBlue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.porcelainMist.opacity(0.86), in: Capsule())
                Spacer()
                if !dream.isArchived {
                    PhotosPicker(selection: $selectedAlbumPhotos, matching: .images) {
                        Image(systemName: "plus")
                            .font(.headline.weight(.black))
                            .frame(width: 42, height: 42)
                            .background(Color.porcelainBlue, in: Circle())
                            .foregroundStyle(.white)
                    }
                    .onChange(of: selectedAlbumPhotos) { _, items in
                        Task { await importAlbumImages(from: items) }
                    }
                }
            }

            if dream.imagePaths.isEmpty {
                Label(copy("先添加一张让你心动的画面", "Add a photo that inspires you"), systemImage: "photo.stack")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.porcelainBlue)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.porcelainMist.opacity(0.86), in: Capsule())
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(dream.imagePaths.enumerated()), id: \.element) { index, path in
                            Button {
                                previewImage = ImagePreview(path: path)
                            } label: {
                                DreamImage(path: path, height: 116)
                                    .frame(width: index == 0 ? 150 : 116, height: 116)
                                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                    .overlay(alignment: .topLeading) {
                                        if index == 0 {
                                            Image(systemName: "star.fill")
                                                .font(.caption.weight(.black))
                                                .padding(8)
                                                .background(Color.porcelainBlue.opacity(0.92), in: Circle())
                                                .foregroundStyle(.white)
                                                .padding(7)
                                        }
                                    }
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                                            .stroke(.white.opacity(0.92), lineWidth: 2)
                                    }
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                if !dream.isArchived {
                                    Button { setCover(path) } label: {
                                        Label(copy("设为封面", "Set as cover"), systemImage: "star")
                                    }
                                    Button(role: .destructive) { deleteAlbumImage(path) } label: {
                                        Label(copy("删除画面", "Delete photo"), systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 2)
                }
            }
        }
        .padding(18)
        .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            PorcelainRimOverlay(cornerRadius: 26)
        }
    }

    private var collageVisionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CollageSectionTitle(title: copy("梦想描述", "Vision"))
                Spacer()
                if !dream.isArchived {
                    Menu {
                        Button {
                            isEditingVision = true
                        } label: {
                            Label(dream.visionText.isEmpty ? copy("填写", "Add") : copy("编辑", "Edit"), systemImage: "pencil")
                        }
                        if !dream.visionText.isEmpty {
                            Button(role: .destructive) {
                                updateVisionText("")
                            } label: {
                                Label(copy("删除", "Delete"), systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .frame(width: 36, height: 36)
                            .background(.white.opacity(0.62), in: Circle())
                    }
                }
            }
            Text(dream.visionText.isEmpty ? copy("暂无描述。", "No description.") : dream.visionText)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.albumInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .collageCard(cornerRadius: 26, opacity: 0.78)
    }

    private var collageGallerySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                CollageSectionTitle(title: copy("全部画面", "All Photos"), subtitle: dream.imagePaths.isEmpty ? copy("0 张", "0 photos") : copy("\(dream.imagePaths.count) 张", "\(dream.imagePaths.count) photos"))
                Spacer()
                if !dream.isArchived {
                    PhotosPicker(selection: $selectedAlbumPhotos, matching: .images) {
                        Image(systemName: "plus")
                            .font(.headline.weight(.black))
                            .frame(width: 42, height: 42)
                            .background(Color.dopamineBlue, in: Circle())
                            .foregroundStyle(.white)
                    }
                    .onChange(of: selectedAlbumPhotos) { _, items in
                        Task { await importAlbumImages(from: items) }
                    }
                }
            }

            if dream.imagePaths.isEmpty {
                CollageSticker(text: copy("先添加一张让你心动的画面", "Add a photo that inspires you"), symbol: "photo", tint: Color.albumGreen, fill: Color.white.opacity(0.72))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(dream.imagePaths.enumerated()), id: \.element) { index, path in
                            Button {
                                previewImage = ImagePreview(path: path)
                            } label: {
                                DreamImage(path: path, height: 116)
                                    .frame(width: index == 0 ? 150 : 116, height: 116)
                                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                    .overlay(alignment: .topLeading) {
                                        if index == 0 {
                                            Image(systemName: "star.fill")
                                                .font(.caption.weight(.black))
                                                .padding(8)
                                                .background(.black.opacity(0.34), in: Circle())
                                                .foregroundStyle(.white)
                                                .padding(7)
                                        }
                                    }
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .stroke(.white.opacity(0.86), lineWidth: 2)
                                    }
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                if !dream.isArchived {
                                    Button {
                                        setCover(path)
                                    } label: {
                                        Label(copy("设为封面", "Set as cover"), systemImage: "star")
                                    }
                                    Button(role: .destructive) {
                                        deleteAlbumImage(path)
                                    } label: {
                                        Label(copy("删除画面", "Delete photo"), systemImage: "trash")
                                    }
                                }
                            }
                            .rotationEffect(.degrees(index.isMultiple(of: 2) ? -2.2 : 2.2))
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 2)
                }
            }
        }
        .padding(18)
        .collageCard(cornerRadius: 26, opacity: 0.78)
    }

    private var visionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Label(copy("梦想描述", "Vision"), systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(LibraryStyle.mint)
                Spacer()
                if !dream.isArchived {
                    Menu {
                        Button {
                            isEditingVision = true
                        } label: {
                            Label(dream.visionText.isEmpty ? copy("填写", "Add") : copy("编辑", "Edit"), systemImage: "pencil")
                        }

                        if !dream.visionText.isEmpty {
                            Button(role: .destructive) {
                                updateVisionText("")
                            } label: {
                                Label(copy("删除", "Delete"), systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel(copy("描述操作", "Vision actions"))
                }
            }
            Text(dream.visionText.isEmpty ? copy("暂无描述。", "No description.") : dream.visionText)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(LibraryStyle.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var albumGallerySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(copy("全部画面", "All Photos"))
                        .font(.title3.bold())
                    Text(dream.imagePaths.isEmpty ? copy("暂无照片", "No photos yet") : copy("共 \(dream.imagePaths.count) 张画面", "\(dream.imagePaths.count) photos total"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !dream.isArchived {
                    HStack(spacing: 8) {
                        PhotosPicker(selection: $selectedAlbumPhotos, matching: .images) {
                            Label(copy("从相册添加", "Add from Library"), systemImage: "photo.on.rectangle")
                                .labelStyle(.iconOnly)
                                .font(.headline)
                                .frame(width: 44, height: 44)
                                .background(LibraryStyle.mint, in: Circle())
                                .foregroundStyle(LibraryStyle.background)
                        }
                        .onChange(of: selectedAlbumPhotos) { _, items in
                            Task { await importAlbumImages(from: items) }
                        }

                        if CameraCaptureView.isCameraAvailable {
                            Button {
                                isShowingAlbumCamera = true
                            } label: {
                                Label(copy("拍照添加", "Take Photo"), systemImage: "camera.fill")
                                    .labelStyle(.iconOnly)
                                    .font(.headline)
                                    .frame(width: 44, height: 44)
                                    .background(LibraryStyle.mint, in: Circle())
                                    .foregroundStyle(LibraryStyle.background)
                            }
                        }
                    }
                }
            }

            if dream.imagePaths.isEmpty {
                Text(copy("添加照片。", "Add photos."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(LibraryStyle.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                LazyVGrid(columns: galleryColumns, spacing: 8) {
                    ForEach(dream.imagePaths, id: \.self) { path in
                    Button {
                        previewImage = ImagePreview(path: path)
                    } label: {
                        DreamImage(path: path, height: 104)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(alignment: .topLeading) {
                                    if path == dream.imagePaths.first {
                                        Image(systemName: "star.fill")
                                            .font(.caption)
                                            .padding(7)
                                            .background(.black.opacity(0.35), in: Circle())
                                            .foregroundStyle(.white)
                                            .padding(6)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if !dream.isArchived {
                                Button {
                                    setCover(path)
                                } label: {
                                    Label(copy("设为封面", "Set as cover"), systemImage: "star")
                                }
                                Button(role: .destructive) {
                                    deleteAlbumImage(path)
                                } label: {
                                    Label(copy("删除画面", "Delete photo"), systemImage: "trash")
                                }
                            }
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(.white.opacity(0.10), lineWidth: 1)
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(LibraryStyle.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var galleryColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8)
        ]
    }

    private var archivedBanner: some View {
                Label(copy("此梦想已归档，内容只读", "This dream is archived and read-only"), systemImage: "archivebox.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(LibraryStyle.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var selectedRecordDate: Date {
        recordDate
    }

    private var recordSectionTitle: String {
        copy("添加成长记录", "Add Growth Record")
    }

    private var completionToastTitle: String {
        copy("已保存", "Record saved")
    }

    private var dailyRecordSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(recordSectionTitle)
                    .font(.title3.bold())
                    .foregroundStyle(isBeachStyle ? Color.beachSeaBlue : Color.primary)
                Text(copy("记录进展。", "Record your progress."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            DatePicker(copy("记录日期", "Record date"), selection: $recordDate, displayedComponents: .date)
                .datePickerStyle(.compact)

            TextEditor(text: $recordText)
                .frame(minHeight: 116)
                .padding(10)
                .focused($isRecordFocused)
                .scrollContentBackground(.hidden)
                .background(LibraryStyle.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if recordText.isEmpty {
                        Text(copy("写下一条成长记录", "Write a growth record"))
                            .foregroundStyle(.secondary.opacity(0.75))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    Text("\(recordText.count)/200")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(10)
                }
                .onChange(of: recordText) { _, newValue in
                    if newValue.count > 200 {
                        recordText = String(newValue.prefix(200))
                    }
                }

            HStack(spacing: 14) {
                PhotosPicker(selection: $selectedRecordPhotos, matching: .images) {
                    Label(recordImagePaths.isEmpty ? copy("从相册添加", "Add from Library") : copy("继续选择", "Add from Library"), systemImage: "photo")
                        .foregroundStyle(isBeachStyle ? Color.beachSeaBlue : Color.accentColor)
                }
                .onChange(of: selectedRecordPhotos) { _, items in
                    Task { await importRecordImages(from: items) }
                }
                if CameraCaptureView.isCameraAvailable {
                    Button {
                        isShowingRecordCamera = true
                    } label: {
                        Label(copy("拍照", "Take Photo"), systemImage: "camera.fill")
                            .foregroundStyle(isBeachStyle ? Color.beachSeaBlue : Color.accentColor)
                    }
                    .buttonStyle(.borderless)
                }
                Spacer()
            }

            if !recordImagePaths.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(recordImagePaths, id: \.self) { path in
                            DreamImage(path: path, height: 120)
                                .frame(width: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(alignment: .topTrailing) {
                                    Button {
                                        recordImagePaths.removeAll { $0 == path }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.headline)
                                            .symbolRenderingMode(.hierarchical)
                                            .foregroundStyle(.white)
                                            .padding(6)
                                    }
                                }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            if requiresMood {
                VStack(alignment: .leading, spacing: 10) {
                    Text(copy("心情", "Mood"))
                        .font(.subheadline.weight(.semibold))
                    HStack(spacing: 12) {
                        ForEach(DreamMood.allCases) { mood in
                            Button {
                                selectedMood = mood
                            } label: {
                                Label(mood.title, systemImage: mood.symbol)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(MoodButtonStyle(isSelected: selectedMood == mood))
                        }
                    }
                }
            }

            Button {
                submitRecord()
            } label: {
                Text(buttonTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(detailActionTint)
            .foregroundStyle(canSubmitRecord ? LibraryStyle.background : Color.secondary)
            .disabled(!canSubmitRecord)
        }
        .padding(18)
        .background(detailSectionFill, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            if isBeachStyle {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.88), lineWidth: 1.5)
            }
        }
        .shadow(color: isBeachStyle ? Color.beachSeaBlue.opacity(0.09) : .clear, radius: 14, y: 8)
        .onChange(of: recordDate) { _, _ in
            isRecordFocused = true
        }
    }

    private var canSubmitRecord: Bool {
        !recordText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (!requiresMood || selectedMood != nil)
    }

    private var buttonTitle: String {
        let trimmed = recordText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return copy("填写记录", "Add a record") }
        if requiresMood && selectedMood == nil { return copy("选择心情", "Choose mood") }
        return copy("保存成长记录", "Save growth record")
    }

    private var requiresMood: Bool {
        store.isMoodChartEnabled
    }

    private var stageSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(copy("下一步", "Next Step"))
                .font(.title3.bold())
                .foregroundStyle(isBeachStyle ? Color.beachSeaBlue : Color.primary)

            HStack(spacing: 10) {
                TextField(copy("下一步计划", "Next step"), text: $newStageTitle)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(LibraryStyle.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Button(action: addStage) {
                    Image(systemName: "plus")
                        .font(.headline)
                        .frame(width: 42, height: 42)
                        .background(detailActionTint, in: Circle())
                        .foregroundStyle(LibraryStyle.background)
                }
                .disabled(newStageTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || dream.isArchived)
                .opacity(newStageTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || dream.isArchived ? 0.45 : 1)
            }

            Toggle(isOn: $newStageHasTargetDate) {
                Label(copy("设置目标日期", "Set target date"), systemImage: "calendar")
            }
            .font(.subheadline.weight(.semibold))
            .disabled(dream.isArchived)

            if newStageHasTargetDate {
                DatePicker(copy("期待日期", "Target date"), selection: $newStageTargetDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .disabled(dream.isArchived)
            }

            if dream.milestones.isEmpty {
                Text(copy("暂无计划。", "No plans yet."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(dream.milestones) { stage in
                    HStack(spacing: 10) {
                        Button {
                            toggleStage(stage)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: stage.isDone ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(stage.isDone ? detailActionTint : .secondary)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(stage.title)
                                        .font(.subheadline.weight(.semibold))
                                        .strikethrough(stage.isDone, color: .secondary)
                                    if let targetDate = stage.targetDate {
                                        Text(copy("期待在 \(targetDate.formatted(date: .abbreviated, time: .omitted)) 前推进", "Before \(targetDate.formatted(date: .abbreviated, time: .omitted))"))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else if stage.isDone, let doneAt = stage.doneAt {
                                        Text(copy("完成于 \(doneAt.formatted(date: .abbreviated, time: .omitted))", "Completed \(doneAt.formatted(date: .abbreviated, time: .omitted))"))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(dream.isArchived)

                        Menu {
                            Button {
                                editingStage = stage
                            } label: {
                                Label(copy("编辑下一步", "Edit next step"), systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                deleteStage(stage)
                            } label: {
                                Label(copy("删除下一步", "Delete next step"), systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .frame(width: 34, height: 34)
                                .background(LibraryStyle.surface, in: Circle())
                        }
                        .disabled(dream.isArchived)
                    }
                    .padding(12)
                    .background(LibraryStyle.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
        .padding(18)
        .background(detailSectionFill, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            if isBeachStyle {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.88), lineWidth: 1.5)
            }
        }
        .shadow(color: isBeachStyle ? Color.beachSeaBlue.opacity(0.09) : .clear, radius: 14, y: 8)
    }

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(copy("成长足迹", "Growth Timeline"))
                .font(.title3.bold())

            if dream.timelineItems.isEmpty {
                Text(copy("暂无记录。", "No records yet."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(dream.timelineItems) { item in
                    TimelineRow(
                        item: item,
                        onEdit: { log in editingLog = log },
                        onDelete: { log in deleteLog(log) }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var growthFootprintSection: some View {
        if store.timelineDisplayStyle == .timeline {
            timelineSection
        } else {
            VStack(alignment: .leading, spacing: 16) {
                Text(copy("成长足迹", "Growth Timeline")).font(.title3.bold())
                if dream.timelineItems.isEmpty {
                    Text(copy("暂无记录。", "No records yet."))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(dream.timelineItems) { item in
                    TimelineRow(item: item, showConnector: false,
                                onEdit: { editingLog = $0 }, onDelete: { deleteLog($0) })
                }
            }
        }
    }

    private var beachTimelineSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .bottom) {
                Text(copy("成长足迹", "Growth Timeline"))
                    .font(.title3.bold())
                    .foregroundStyle(Color.beachSeaBlue)
                Spacer()
                if !dream.timelineItems.isEmpty {
                    Text(copy("\(dream.timelineItems.count) 条", "\(dream.timelineItems.count) items"))
                        .font(.caption.weight(.black))
                        .foregroundStyle(Color.beachSeaBlue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.72), in: Capsule())
                }
            }

            BeachWaveDivider(color: .beachSeaBlue)

            if dream.timelineItems.isEmpty {
                BeachSectionCard {
                    Text(copy("暂无记录。", "No records yet."))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.albumInk.opacity(0.62))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ForEach(Array(dream.timelineItems.enumerated()), id: \.element.id) { index, item in
                    BeachTimelineRow(
                        item: item,
                        isLast: index == dream.timelineItems.count - 1,
                        onEdit: { log in editingLog = log },
                        onDelete: { log in deleteLog(log) }
                    )
                }
            }
        }
    }

    private var beachTimelineCardSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .bottom) {
                Text(copy("成长足迹", "Growth Timeline"))
                    .font(.title3.bold())
                    .foregroundStyle(Color.beachSeaBlue)
                Spacer()
                if !dream.timelineItems.isEmpty {
                    Text(copy("\(dream.timelineItems.count) 条", "\(dream.timelineItems.count) items"))
                        .font(.caption.weight(.black))
                        .foregroundStyle(Color.beachSeaBlue)
                }
            }

            BeachWaveDivider(color: .beachSeaBlue)

            if dream.timelineItems.isEmpty {
                BeachSectionCard {
                    Text(copy("暂无记录。", "No records yet."))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.albumInk.opacity(0.62))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ForEach(dream.timelineItems) { item in
                    BeachTimelineCard(
                        item: item,
                        onEdit: { log in editingLog = log },
                        onDelete: { log in deleteLog(log) }
                    )
                }
            }
        }
    }

    private var collageTimelineSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            CollageSectionTitle(title: copy("成长足迹", "Growth Timeline"), subtitle: dream.timelineItems.isEmpty ? nil : copy("\(dream.timelineItems.count) 条", "\(dream.timelineItems.count) items"))

            if dream.timelineItems.isEmpty {
                Text(copy("暂无记录。", "No records yet."))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(18)
                    .collageCard(cornerRadius: 22)
            } else {
                ForEach(Array(dream.timelineItems.enumerated()), id: \.element.id) { index, item in
                    CollageTimelineCard(
                        item: item,
                        rotation: index.isMultiple(of: 2) ? -0.8 : 0.8,
                        onEdit: { log in editingLog = log },
                        onDelete: { log in deleteLog(log) }
                    )
                }
            }
        }
    }

    private func submitRecord() {
        let moodForLog = requiresMood ? selectedMood : .positive
        guard let moodForLog else { return }
        let targetDate = selectedRecordDate
        let message = completionToastTitle
        var copy = dream
        copy.logs.append(DreamLog(
            action: recordText.trimmingCharacters(in: .whitespacesAndNewlines),
            mood: moodForLog,
            date: targetDate,
            imagePaths: recordImagePaths
        ))
        dream = copy
        store.update(copy)
        recordText = ""
        self.selectedMood = nil
        recordImagePaths = []
        selectedRecordPhotos = []
        completionMessage = message
        showCompletionToast(message)
    }

    private func importRecordImages(from items: [PhotosPickerItem]) async {
        let paths = await importImages(from: items)
        recordImagePaths.append(contentsOf: paths)
        selectedRecordPhotos = []
    }

    private func importAlbumImages(from items: [PhotosPickerItem]) async {
        let paths = await importImages(from: items)
        guard !paths.isEmpty else { return }
        var copy = dream
        copy.imagePaths.append(contentsOf: paths)
        dream = copy
        store.update(copy)
        selectedAlbumPhotos = []
    }

    private func saveCapturedAlbumImage(_ image: UIImage) {
        guard let path = saveCapturedImage(image) else { return }
        var copy = dream
        copy.imagePaths.append(path)
        dream = copy
        store.update(copy)
    }

    private func saveCapturedRecordImage(_ image: UIImage) {
        guard let path = saveCapturedImage(image) else { return }
        recordImagePaths.append(path)
    }

    private func saveCapturedImage(_ image: UIImage) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.92) else { return nil }
        return try? ImageLibrary.saveImageData(data)
    }

    private func importImages(from items: [PhotosPickerItem]) async -> [String] {
        var paths: [String] = []
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let path = try? ImageLibrary.saveImageData(data) else { continue }
            paths.append(path)
        }
        return paths
    }

    private func setCover(_ path: String) {
        guard let index = dream.imagePaths.firstIndex(of: path), index != 0 else { return }
        var copy = dream
        let cover = copy.imagePaths.remove(at: index)
        copy.imagePaths.insert(cover, at: 0)
        dream = copy
        store.update(copy)
    }

    private func deleteAlbumImage(_ path: String) {
        var copy = dream
        copy.imagePaths.removeAll { $0 == path }
        dream = copy
        store.update(copy)
    }

    private func updateVisionText(_ text: String) {
        var copy = dream
        copy.visionText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        dream = copy
        store.update(copy)
        showCompletionToast(copy.visionText.isEmpty ? "实现画面已清空" : "实现画面已更新")
    }

    private func updateDreamTitle(_ title: String) {
        var copy = dream
        copy.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        dream = copy
        store.update(copy)
        showCompletionToast("相册名称已更新")
    }

    private func updateLog(_ log: DreamLog) {
        var copy = dream
        guard let index = copy.logs.firstIndex(where: { $0.id == log.id }) else { return }
        copy.logs[index] = log
        dream = copy
        store.update(copy)
        showCompletionToast("已更新")
    }

    private func deleteLog(_ log: DreamLog) {
        var copy = dream
        copy.logs.removeAll { $0.id == log.id }
        dream = copy
        store.update(copy)
        showCompletionToast("已删除")
    }

    @MainActor
    private func shareAlbum() {
        let poster = SharePosterView(dream: dream)
            .environment(\.colorScheme, .light)
            .frame(width: 1080, height: 1920)
            .environmentObject(store)
        let renderer = ImageRenderer(content: poster)
        renderer.scale = 1
        if let image = renderer.uiImage {
            posterPreviewImage = image
        } else {
            shareError = true
        }
    }

    private func addStage() {
        let title = newStageTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        var copy = dream
        copy.milestones.append(DreamStage(title: title, targetDate: newStageHasTargetDate ? newStageTargetDate : nil))
        dream = copy
        store.update(copy)
        newStageTitle = ""
        newStageHasTargetDate = false
        newStageTargetDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    }

    private func toggleStage(_ stage: DreamStage) {
        var copy = dream
        guard let index = copy.milestones.firstIndex(where: { $0.id == stage.id }) else { return }
        copy.milestones[index].isDone.toggle()
        copy.milestones[index].doneAt = copy.milestones[index].isDone ? Date() : nil
        dream = copy
        store.update(copy)
        if copy.milestones[index].isDone {
            showCompletionToast("完成下一步：\(copy.milestones[index].title)")
        }
    }

    private func updateStage(_ stage: DreamStage) {
        var copy = dream
        guard let index = copy.milestones.firstIndex(where: { $0.id == stage.id }) else { return }
        copy.milestones[index] = stage
        dream = copy
        store.update(copy)
        showCompletionToast("下一步已更新")
    }

    private func deleteStage(_ stage: DreamStage) {
        var copy = dream
        copy.milestones.removeAll { $0.id == stage.id }
        dream = copy
        store.update(copy)
        showCompletionToast("下一步已删除")
    }

    private func showCompletionToast(_ message: String) {
        completionMessage = message
        withAnimation { showCompletion = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation { showCompletion = false }
        }
    }

    private func copy(_ chinese: String, _ english: String) -> String {
        AlbumCopy.pick(store.appLanguage, chinese, english)
    }

    private func hasLog(on date: Date) -> Bool {
        dream.logs.contains { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }
}

private struct MoodButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.vertical, 12)
            .background(isSelected ? LibraryStyle.mint.opacity(0.18) : LibraryStyle.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .foregroundStyle(isSelected ? LibraryStyle.mint : .primary)
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? LibraryStyle.mint.opacity(0.45) : Color.clear)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

private struct PosterPreviewSheet: View {
    @EnvironmentObject private var store: DreamStore
    @Environment(\.dismiss) private var dismiss
    let image: UIImage
    let onShare: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                LibraryStyle.background.ignoresSafeArea()
                VStack(spacing: 18) {
                    ScrollView(.vertical, showsIndicators: false) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .shadow(color: .black.opacity(0.28), radius: 22, y: 12)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 18)
                    }

                    Button {
                        onShare()
                    } label: {
                        Label(copy("确认分享", "Share"), systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(LibraryStyle.mint)
                    .foregroundStyle(LibraryStyle.background)
                    .controlSize(.large)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)
                }
            }
            .navigationTitle(copy("预览分享图", "Preview Share Image"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(copy("取消", "Cancel")) {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    private func copy(_ chinese: String, _ english: String) -> String {
        AlbumCopy.pick(store.appLanguage, chinese, english)
    }
}

private struct DreamVisionEditorSheet: View {
    @EnvironmentObject private var store: DreamStore
    @Environment(\.dismiss) private var dismiss
    let onSave: (String) -> Void
    @State private var text: String

    init(text: String, onSave: @escaping (String) -> Void) {
        _text = State(initialValue: text)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 140)
                        .onChange(of: text) { _, newValue in
                            if newValue.count > 120 {
                                text = String(newValue.prefix(120))
                            }
                        }
                    Text("\(text.count)/120")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text(copy("梦想描述", "Vision"))
                } footer: {
                    Text(copy("写得越具体，梦想越容易被看见。", "The more specific it is, the easier the dream becomes to see."))
                }
            }
            .scrollContentBackground(.hidden)
            .background(LibraryStyle.background)
            .navigationTitle(copy("编辑描述", "Edit Vision"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(copy("取消", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(copy("保存", "Save")) {
                        onSave(text)
                        dismiss()
                    }
                }
            }
        }
    }

    private func copy(_ chinese: String, _ english: String) -> String {
        AlbumCopy.pick(store.appLanguage, chinese, english)
    }
}

private struct DreamLogEditorSheet: View {
    @EnvironmentObject private var store: DreamStore
    @Environment(\.dismiss) private var dismiss
    let originalLog: DreamLog
    let onSave: (DreamLog) -> Void

    @State private var action: String
    @State private var mood: DreamMood
    @State private var date: Date
    @State private var imagePaths: [String]
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var isShowingCamera = false

    init(log: DreamLog, onSave: @escaping (DreamLog) -> Void) {
        originalLog = log
        self.onSave = onSave
        _action = State(initialValue: log.action)
        _mood = State(initialValue: log.mood)
        _date = State(initialValue: log.date)
        _imagePaths = State(initialValue: log.imagePaths)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(copy("成长记录", "Growth Record")) {
                    TextEditor(text: $action)
                        .frame(minHeight: 130)
                        .onChange(of: action) { _, newValue in
                            if newValue.count > 200 {
                                action = String(newValue.prefix(200))
                            }
                        }
                    Text("\(action.count)/200")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section(copy("日期和感觉", "Date and Mood")) {
                    DatePicker(copy("记录日期", "Record date"), selection: $date, displayedComponents: .date)
                    HStack(spacing: 12) {
                        ForEach(DreamMood.allCases) { item in
                            Button {
                                mood = item
                            } label: {
                                Label(item.title, systemImage: item.symbol)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(MoodButtonStyle(isSelected: mood == item))
                        }
                    }
                    .buttonStyle(.plain)
                }

                Section(copy("记录画面", "Record Photos")) {
                    HStack(spacing: 14) {
                        PhotosPicker(selection: $selectedPhotos, matching: .images) {
                            Label(imagePaths.isEmpty ? copy("从相册添加", "Add from Library") : copy("继续选择", "Add from Library"), systemImage: "photo.on.rectangle")
                        }
                        .onChange(of: selectedPhotos) { _, items in
                            Task { await importImages(from: items) }
                        }

                        if CameraCaptureView.isCameraAvailable {
                            Button {
                                isShowingCamera = true
                            } label: {
                                Label(copy("拍照", "Take Photo"), systemImage: "camera.fill")
                            }
                            .buttonStyle(.borderless)
                        }
                    }

                    if !imagePaths.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(imagePaths, id: \.self) { path in
                                    DreamImage(path: path, height: 112)
                                        .frame(width: 112)
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                        .overlay(alignment: .topTrailing) {
                                            Button {
                                                imagePaths.removeAll { $0 == path }
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.headline)
                                                    .symbolRenderingMode(.hierarchical)
                                                    .foregroundStyle(.white)
                                                    .padding(6)
                                            }
                                        }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(LibraryStyle.background)
            .navigationTitle(copy("编辑成长记录", "Edit Record"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(copy("取消", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(copy("保存", "Save")) {
                        var updated = originalLog
                        updated.action = action.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.mood = mood
                        updated.date = date
                        updated.imagePaths = imagePaths
                        onSave(updated)
                        dismiss()
                    }
                    .disabled(action.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .sheet(isPresented: $isShowingCamera) {
                CameraCaptureView { image in
                    saveCapturedImage(image)
                }
                .ignoresSafeArea()
            }
        }
    }

    private func importImages(from items: [PhotosPickerItem]) async {
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let path = try? ImageLibrary.saveImageData(data) else { continue }
            imagePaths.append(path)
        }
        selectedPhotos = []
    }

    private func saveCapturedImage(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.92),
              let path = try? ImageLibrary.saveImageData(data) else { return }
        imagePaths.append(path)
    }

    private func copy(_ chinese: String, _ english: String) -> String {
        AlbumCopy.pick(store.appLanguage, chinese, english)
    }
}

private struct DreamStageEditorSheet: View {
    @EnvironmentObject private var store: DreamStore
    @Environment(\.dismiss) private var dismiss
    let originalStage: DreamStage
    let onSave: (DreamStage) -> Void

    @State private var title: String
    @State private var hasTargetDate: Bool
    @State private var targetDate: Date
    @State private var isDone: Bool

    init(stage: DreamStage, onSave: @escaping (DreamStage) -> Void) {
        originalStage = stage
        self.onSave = onSave
        _title = State(initialValue: stage.title)
        _hasTargetDate = State(initialValue: stage.targetDate != nil)
        _targetDate = State(initialValue: stage.targetDate ?? Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date())
        _isDone = State(initialValue: stage.isDone)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(copy("下一步内容", "Next Step")) {
                    TextField(copy("写下这个下一步", "Write this next step"), text: $title)
                        .onChange(of: title) { _, newValue in
                            if newValue.count > 18 {
                                title = String(newValue.prefix(18))
                            }
                        }
                    Text("\(title.count)/18")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section(copy("日期和状态", "Date and Status")) {
                    Toggle(copy("加一个期待日期", "Add a target date"), isOn: $hasTargetDate)
                    if hasTargetDate {
                        DatePicker(copy("期待日期", "Target date"), selection: $targetDate, displayedComponents: .date)
                    }
                    Toggle(copy("已完成", "Completed"), isOn: $isDone)
                }
            }
            .scrollContentBackground(.hidden)
            .background(LibraryStyle.background)
            .navigationTitle(copy("编辑下一步", "Edit Next Step"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(copy("取消", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(copy("保存", "Save")) {
                        var updated = originalStage
                        updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.targetDate = hasTargetDate ? targetDate : nil
                        if updated.isDone != isDone {
                            updated.doneAt = isDone ? Date() : nil
                        }
                        updated.isDone = isDone
                        onSave(updated)
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

private struct CollageTimelineCard: View {
    @EnvironmentObject private var store: DreamStore
    let item: DreamTimelineItem
    let rotation: Double
    var onEdit: (DreamLog) -> Void = { _ in }
    var onDelete: (DreamLog) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                CollageSticker(text: item.sortDate.formatted(.dateTime.month().day()), symbol: "calendar", tint: dotColor, fill: dotColor.opacity(0.12))
                Spacer()
                label
                if case .log(let log) = item {
                    Menu {
                        Button {
                            onEdit(log)
                        } label: {
                            Label(copy("编辑记录", "Edit record"), systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            onDelete(log)
                        } label: {
                            Label(copy("删除记录", "Delete record"), systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .frame(width: 34, height: 34)
                            .background(.white.opacity(0.60), in: Circle())
                    }
                }
            }

            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.albumInk)
                .fixedSize(horizontal: false, vertical: true)

            if !imagePaths.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(imagePaths, id: \.self) { path in
                            DreamImage(path: path, height: 108)
                                .frame(width: 108)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(.white.opacity(0.86), lineWidth: 2)
                                }
                        }
                    }
                }
            }
        }
        .padding(16)
        .collageCard(cornerRadius: 22)
        .rotationEffect(.degrees(rotation))
    }

    private var title: String {
        switch item {
        case .log(let log):
            return log.action
        case .stage(let stage):
            return copy("完成下一步：\(stage.title)", "Completed step: \(stage.title)")
        }
    }

    private var imagePaths: [String] {
        guard case .log(let log) = item else { return [] }
        return log.imagePaths
    }

    private var dotColor: Color {
        switch item {
        case .log:
            return Color.albumGreen
        case .stage:
            return Color.softGold
        }
    }

    @ViewBuilder
    private var label: some View {
        switch item {
        case .log(let log):
            Label(log.mood.title, systemImage: log.mood.symbol)
                .font(.caption.weight(.black))
                .foregroundStyle(log.mood == .positive ? Color.albumGreen : .secondary)
        case .stage:
            Label(copy("下一步", "Next step"), systemImage: "flag.fill")
                .font(.caption.weight(.black))
                .foregroundStyle(Color.softGold)
        }
    }

    private func copy(_ chinese: String, _ english: String) -> String {
        AlbumCopy.pick(store.appLanguage, chinese, english)
    }
}

private struct BeachTimelineRow: View {
    @EnvironmentObject private var store: DreamStore
    let item: DreamTimelineItem
    let isLast: Bool
    var onEdit: (DreamLog) -> Void = { _ in }
    var onDelete: (DreamLog) -> Void = { _ in }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 7) {
                node
                if !isLast {
                    Rectangle()
                        .fill(Color.beachSeaBlue.opacity(0.30))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                        .frame(minHeight: 92)
                }
            }
            .frame(width: 26)

            timelineContent
                .padding(15)
                .background(
                    LinearGradient(
                        colors: [Color.white.opacity(0.93), Color.beachSand.opacity(0.76)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.90), lineWidth: 1.5)
                }
                .shadow(color: Color.beachSeaBlue.opacity(0.08), radius: 12, y: 7)
        }
    }

    @ViewBuilder
    private var node: some View {
        switch item {
        case .log:
            Circle()
                .fill(Color.beachSeaBlue)
                .frame(width: 13, height: 13)
                .overlay { Circle().stroke(Color.white, lineWidth: 3).padding(-3) }
        case .stage:
            BeachShellMark()
                .fill(Color.softGold)
                .frame(width: 24, height: 21)
                .overlay { BeachShellMark().stroke(Color.white.opacity(0.86), lineWidth: 1.5) }
        }
    }

    private var timelineContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text(item.sortDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.albumInk.opacity(0.54))
                Spacer()
                label
                actionsMenu
            }

            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.albumInk)
                .fixedSize(horizontal: false, vertical: true)

            if !imagePaths.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 9) {
                        ForEach(imagePaths, id: \.self) { path in
                            DreamImage(path: path, height: 104)
                                .frame(width: 104)
                                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                                        .stroke(Color.white.opacity(0.92), lineWidth: 2)
                                }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var actionsMenu: some View {
        if case .log(let log) = item {
            Menu {
                Button { onEdit(log) } label: {
                    Label(copy("编辑记录", "Edit record"), systemImage: "pencil")
                }
                Button(role: .destructive) { onDelete(log) } label: {
                    Label(copy("删除记录", "Delete record"), systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.headline)
                    .foregroundStyle(Color.albumInk.opacity(0.56))
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.68), in: Circle())
            }
        }
    }

    @ViewBuilder
    private var label: some View {
        switch item {
        case .log(let log):
            Label(log.mood.title, systemImage: log.mood.symbol)
                .font(.caption.weight(.black))
                .foregroundStyle(log.mood == .positive ? Color.beachSeaBlue : Color.albumInk.opacity(0.52))
        case .stage:
            Text(copy("下一步", "Next step"))
                .font(.caption.weight(.black))
                .foregroundStyle(Color.softGold)
        }
    }

    private var title: String {
        switch item {
        case .log(let log): return log.action
        case .stage(let stage): return copy("完成下一步：\(stage.title)", "Completed step: \(stage.title)")
        }
    }

    private var imagePaths: [String] {
        guard case .log(let log) = item else { return [] }
        return log.imagePaths
    }

    private func copy(_ chinese: String, _ english: String) -> String {
        AlbumCopy.pick(store.appLanguage, chinese, english)
    }
}

private struct BeachTimelineCard: View {
    @EnvironmentObject private var store: DreamStore
    let item: DreamTimelineItem
    var onEdit: (DreamLog) -> Void = { _ in }
    var onDelete: (DreamLog) -> Void = { _ in }

    var body: some View {
        BeachSectionCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(item.sortDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption.weight(.black))
                        .foregroundStyle(Color.beachSeaBlue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.beachSky.opacity(0.72), in: Capsule())
                    Spacer()
                    label
                    actionsMenu
                }

                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.albumInk)
                    .fixedSize(horizontal: false, vertical: true)

                if !imagePaths.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 9) {
                            ForEach(imagePaths, id: \.self) { path in
                                DreamImage(path: path, height: 104)
                                    .frame(width: 104)
                                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                                            .stroke(Color.white.opacity(0.92), lineWidth: 2)
                                    }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var actionsMenu: some View {
        if case .log(let log) = item {
            Menu {
                Button { onEdit(log) } label: {
                    Label(copy("编辑记录", "Edit record"), systemImage: "pencil")
                }
                Button(role: .destructive) { onDelete(log) } label: {
                    Label(copy("删除记录", "Delete record"), systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.headline)
                    .foregroundStyle(Color.albumInk.opacity(0.56))
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.68), in: Circle())
            }
        }
    }

    @ViewBuilder
    private var label: some View {
        switch item {
        case .log(let log):
            Label(log.mood.title, systemImage: log.mood.symbol)
                .font(.caption.weight(.black))
                .foregroundStyle(log.mood == .positive ? Color.beachSeaBlue : Color.albumInk.opacity(0.52))
        case .stage:
            HStack(spacing: 6) {
                BeachShellMark()
                    .fill(Color.softGold)
                    .frame(width: 18, height: 16)
                Text(copy("下一步", "Next step"))
            }
            .font(.caption.weight(.black))
            .foregroundStyle(Color.softGold)
        }
    }

    private var title: String {
        switch item {
        case .log(let log): return log.action
        case .stage(let stage): return copy("完成下一步：\(stage.title)", "Completed step: \(stage.title)")
        }
    }

    private var imagePaths: [String] {
        guard case .log(let log) = item else { return [] }
        return log.imagePaths
    }

    private func copy(_ chinese: String, _ english: String) -> String {
        AlbumCopy.pick(store.appLanguage, chinese, english)
    }
}

private struct TimelineRow: View {
    @EnvironmentObject private var store: DreamStore
    let item: DreamTimelineItem
    var showConnector = true
    var onEdit: (DreamLog) -> Void = { _ in }
    var onDelete: (DreamLog) -> Void = { _ in }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            if showConnector {
              VStack(spacing: 6) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 10, height: 10)
                Rectangle()
                    .fill(dotColor.opacity(0.18))
                    .frame(width: 2, height: 86)
              }
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(item.sortDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    label
                    if case .log(let log) = item {
                        Menu {
                            Button {
                                onEdit(log)
                            } label: {
                                Label(copy("编辑记录", "Edit record"), systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                onDelete(log)
                            } label: {
                                Label(copy("删除记录", "Delete record"), systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Text(title)
                    .font(.body)
                if !imagePaths.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(imagePaths, id: \.self) { path in
                                DreamImage(path: path, height: 120)
                                    .frame(width: 120)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }
                    }
                }
            }
            .padding(14)
            .background(LibraryStyle.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contextMenu {
                if case .log(let log) = item {
                    Button {
                        onEdit(log)
                    } label: {
                        Label(copy("编辑记录", "Edit record"), systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        onDelete(log)
                    } label: {
                        Label(copy("删除记录", "Delete record"), systemImage: "trash")
                    }
                }
            }
        }
    }

    private var title: String {
        switch item {
        case .log(let log):
            return log.action
        case .stage(let stage):
            return copy("完成下一步：\(stage.title)", "Completed step: \(stage.title)")
        }
    }

    private var imagePaths: [String] {
        guard case .log(let log) = item else { return [] }
        return log.imagePaths
    }

    private var dotColor: Color {
        switch item {
        case .log:
            return LibraryStyle.mint
        case .stage:
            return Color.softGold
        }
    }

    @ViewBuilder
    private var label: some View {
        switch item {
        case .log(let log):
            Label(log.mood.title, systemImage: log.mood.symbol)
                .font(.caption)
                .foregroundStyle(log.mood == .positive ? LibraryStyle.mint : .secondary)
        case .stage:
            Label(copy("下一步", "Next step"), systemImage: "flag.fill")
                .font(.caption)
                .foregroundStyle(Color.softGold)
        }
    }

    private func copy(_ chinese: String, _ english: String) -> String {
        AlbumCopy.pick(store.appLanguage, chinese, english)
    }
}
