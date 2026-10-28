import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct AlbumHomeView: View {
    @EnvironmentObject private var store: DreamStore
    @EnvironmentObject private var purchaseStore: PurchaseStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.albumBackgroundContrast) private var backgroundContrast
    @State private var isAddingDream = false
    @State private var isShowingPremium = false
    @State private var editingDreamTitle: Dream?
    @State private var draggedDreamID: UUID?
    @State private var dropTargetDreamID: UUID?

    var body: some View {
        NavigationStack {
            ZStack {
                AlbumBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        header

                        if store.activeDreams.isEmpty {
                            EmptyDreamState()
                        } else {
                            EvidenceOverviewCard()
                            homeDreamsContent
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 36)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCreateDream()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                if let dream = store.dreams.first(where: { $0.id == id }) {
                    DreamDetailView(dream: dream)
                }
            }
            .sheet(isPresented: $isAddingDream) {
                NewDreamSheet()
                    .presentationDetents([.large])
            }
            .sheet(isPresented: $isShowingPremium) {
                PremiumUnlockSheet()
                    .environmentObject(store)
                    .environmentObject(purchaseStore)
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: $editingDreamTitle) { dream in
                DreamTitleEditorSheet(title: dream.title) { updatedTitle in
                    updateDreamTitle(dream, title: updatedTitle)
                    editingDreamTitle = nil
                }
                .presentationDetents([.medium])
            }
        }
    }

    @ViewBuilder
    private var homeDreamsContent: some View {
        switch store.settingsDisplayStyle {
        case .magazine:
            magazineHomeContent
        case .compact:
            gridHomeContent
        case .dashboard:
            timelineHomeContent
        default:
            magazineHomeContent
        }
    }

    private var magazineHomeContent: some View {
        VStack(alignment: .leading, spacing: 26) {
            if let featuredDream {
                dreamLink(featuredDream) {
                    FeaturedDreamCard(dream: featuredDream)
                }
            }

            if !secondaryDreams.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: copy("相册集", "Album Collection"), subtitle: copy("\(secondaryDreams.count) 本", "\(secondaryDreams.count) albums"))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(secondaryDreams) { dream in
                                dreamLink(dream) {
                                    DreamGridCard(dream: dream)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private var collageHomeContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            CollageWallTitle()
            collageDreamWallV2
        }
    }

    private var beachHomeContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            BeachWallTitle()
            beachDreamWall
        }
    }

    private var porcelainHomeContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            PorcelainWallTitle()
            porcelainDreamWall
        }
    }

    private var beachDreamWall: some View {
        let dreams = Array(store.activeDreams.prefix(4))
        return VStack(alignment: .leading, spacing: 16) {
            if let mainDream = dreams.first {
                dreamLink(mainDream) {
                    BeachFeaturedAlbumCard(dream: mainDream)
                }
                .modifier(CollageDreamDragDropModifier(
                    dream: mainDream,
                    draggedDreamID: $draggedDreamID,
                    dropTargetDreamID: $dropTargetDreamID,
                    onMove: moveDraggedDream
                ))
            }

            let otherDreams = Array(dreams.dropFirst())
            if !otherDreams.isEmpty {
                if horizontalSizeClass == .regular {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                        ForEach(otherDreams) { dream in
                            dreamLink(dream) {
                                BeachAlbumMiniCard(dream: dream)
                            }
                            .modifier(CollageDreamDragDropModifier(
                                dream: dream,
                                draggedDreamID: $draggedDreamID,
                                dropTargetDreamID: $dropTargetDreamID,
                                onMove: moveDraggedDream
                            ))
                        }
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                        ForEach(otherDreams) { dream in
                            dreamLink(dream) {
                                BeachAlbumMiniCard(dream: dream)
                            }
                            .modifier(CollageDreamDragDropModifier(
                                dream: dream,
                                draggedDreamID: $draggedDreamID,
                                dropTargetDreamID: $dropTargetDreamID,
                                onMove: moveDraggedDream
                            ))
                        }
                    }
                }
            }
        }
    }

    private var porcelainDreamWall: some View {
        let dreams = Array(store.activeDreams.prefix(4))
        return VStack(alignment: .leading, spacing: 16) {
            if let mainDream = dreams.first {
                dreamLink(mainDream) {
                    PorcelainFeaturedAlbumCard(dream: mainDream)
                }
                .modifier(CollageDreamDragDropModifier(
                    dream: mainDream,
                    draggedDreamID: $draggedDreamID,
                    dropTargetDreamID: $dropTargetDreamID,
                    onMove: moveDraggedDream
                ))
            }

            let otherDreams = Array(dreams.dropFirst())
            if !otherDreams.isEmpty {
                LazyVGrid(columns: horizontalSizeClass == .regular ? [
                    GridItem(.flexible(), spacing: 14),
                    GridItem(.flexible(), spacing: 14),
                    GridItem(.flexible(), spacing: 14)
                ] : [
                    GridItem(.flexible(), spacing: 14),
                    GridItem(.flexible(), spacing: 14)
                ], spacing: 14) {
                    ForEach(otherDreams) { dream in
                        dreamLink(dream) {
                            PorcelainMiniAlbumCard(dream: dream)
                        }
                        .modifier(CollageDreamDragDropModifier(
                            dream: dream,
                            draggedDreamID: $draggedDreamID,
                            dropTargetDreamID: $dropTargetDreamID,
                            onMove: moveDraggedDream
                        ))
                    }
                }
            }
        }
    }

    private var collageDreamWallV2: some View {
        let dreams = Array(store.activeDreams.prefix(4))
        return VStack(alignment: .leading, spacing: 16) {
            if let mainDream = dreams.first {
                dreamLink(mainDream) {
                    CollageFeaturedAlbumCard(dream: mainDream)
                }
                .modifier(CollageDreamDragDropModifier(
                    dream: mainDream,
                    draggedDreamID: $draggedDreamID,
                    dropTargetDreamID: $dropTargetDreamID,
                    onMove: moveDraggedDream
                ))
            }

            let otherDreams = Array(dreams.dropFirst())
            if !otherDreams.isEmpty {
                if horizontalSizeClass == .regular {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                        ForEach(Array(otherDreams.enumerated()), id: \.element.id) { index, dream in
                            dreamLink(dream) {
                                CollageAlbumMiniCard(dream: dream, accent: accent(for: index + 1))
                            }
                            .modifier(CollageDreamDragDropModifier(
                                dream: dream,
                                draggedDreamID: $draggedDreamID,
                                dropTargetDreamID: $dropTargetDreamID,
                                onMove: moveDraggedDream
                            ))
                        }
                    }
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(Array(otherDreams.enumerated()), id: \.element.id) { index, dream in
                                dreamLink(dream) {
                                    CollageAlbumMiniCard(dream: dream, accent: accent(for: index + 1))
                                        .frame(width: 176)
                                }
                                .modifier(CollageDreamDragDropModifier(
                                    dream: dream,
                                    draggedDreamID: $draggedDreamID,
                                    dropTargetDreamID: $dropTargetDreamID,
                                    onMove: moveDraggedDream
                                ))
                            }
                        }
                        .padding(.vertical, 3)
                        .padding(.trailing, 4)
                    }
                }
            }
        }
    }

    private var gridHomeContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: copy("梦想画面墙", "Dream Wall"), subtitle: copy("\(store.activeDreams.count) 本", "\(store.activeDreams.count) albums"))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                ForEach(store.activeDreams) { dream in
                    dreamLink(dream) {
                        DreamSquareCard(dream: dream)
                    }
                }
            }
        }
    }

    private var timelineHomeContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: copy("最近记录", "Recent Records"), subtitle: copy("按记录排序", "Sorted by records"))
            VStack(spacing: 12) {
                ForEach(sortedDreams) { dream in
                    dreamLink(dream) {
                        DreamTimelineCard(dream: dream)
                    }
                }
            }
        }
    }

    private var sortedDreams: [Dream] {
        store.activeDreams.sorted { lhs, rhs in
            (lhs.latestLog?.date ?? lhs.createdAt) > (rhs.latestLog?.date ?? rhs.createdAt)
        }
    }

    private func dreamLink<Content: View>(_ dream: Dream, @ViewBuilder content: () -> Content) -> some View {
        NavigationLink(value: dream.id) {
            content()
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                editingDreamTitle = dream
            } label: {
                Label(copy("修改名称", "Rename"), systemImage: "pencil")
            }

            Button {
                store.archive(dream)
            } label: {
                Label(copy("归档", "Archive"), systemImage: "archivebox")
            }
        }
    }

    private var featuredDream: Dream? {
        return store.activeDreams.sorted { lhs, rhs in
            (lhs.latestLog?.date ?? lhs.createdAt) > (rhs.latestLog?.date ?? rhs.createdAt)
        }.first
    }

    private var secondaryDreams: [Dream] {
        guard let featuredDream else { return store.activeDreams }
        return store.activeDreams.filter { $0.id != featuredDream.id }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("DREAM ALBUM")
                    .homeEyebrow()
                    .tracking(3)
                    .foregroundStyle(backgroundContrast == .dark ? Color.white.opacity(0.86) : Color.albumGreen.opacity(0.72))
                Spacer()
                Text(Date().formatted(.dateTime.month().day().weekday(.wide)))
                    .homeCaptionMeta()
                    .foregroundStyle(backgroundContrast == .dark ? Color.white.opacity(0.88) : Color.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(copy("为了梦想", "For Dreams"))
                    .homeTitle()
            }
            .foregroundStyle(backgroundContrast == .dark ? Color.white : Color.albumInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(backgroundContrast == .dark ? 12 : 0)
        .background {
            if backgroundContrast == .dark {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.black.opacity(0.12))
                    .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.16), lineWidth: 1) }
            }
        }
    }

    private var collageHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                Text(Date().formatted(.dateTime.month().day().weekday(.wide)))
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(Color.albumInk.opacity(0.82))
                Spacer()
                Button {} label: {
                    Image(systemName: "magnifyingglass")
                        .font(.title3.weight(.black))
                        .foregroundStyle(Color.albumInk)
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.84), in: Circle())
                        .shadow(color: Color.albumInk.opacity(0.10), radius: 12, y: 7)
                }
                Button {
                    showCreateDream()
                } label: {
                    Image(systemName: "plus")
                        .font(.title2.weight(.black))
                        .foregroundStyle(Color.albumInk)
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.90), in: Circle())
                        .shadow(color: Color.albumInk.opacity(0.10), radius: 12, y: 7)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(copy("为了梦想", "For Dreams"))
                    .font(.system(size: 42, weight: .black, design: .rounded))
                    .foregroundStyle(Color.albumInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                DraggableHomeNote(text: copy("让梦想变具体，让未来在进行时", "Make dreams specific. Keep the future in motion."))
                    .frame(width: 198)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, 4)
            }
        }
    }

    private var beachHeader: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .center) {
                Text(Date().formatted(.dateTime.month().day().weekday(.wide)))
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(Color.albumInk.opacity(0.72))
                Spacer()
                Button {
                    showCreateDream()
                } label: {
                    Image(systemName: "plus")
                        .font(.title2.weight(.black))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(Color.beachSeaBlue, in: Circle())
                        .shadow(color: Color.beachSeaBlue.opacity(0.22), radius: 14, y: 8)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(copy("为了梦想", "For Dreams"))
                        .font(.system(size: store.appLanguage == .english ? 34 : 43, weight: .black, design: .rounded))
                        .foregroundStyle(Color.albumInk)
                        .lineLimit(store.appLanguage == .english ? 2 : 1)
                        .minimumScaleFactor(0.72)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(copy("把心愿晒成一片海", "Let each dream catch the sun"))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.albumInk.opacity(0.58))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                BeachWaveDivider()
                    .frame(maxWidth: 180)
            }
        }
    }

    private var porcelainHeader: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .center) {
                Text(Date().formatted(.dateTime.month().day().weekday(.wide)))
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(Color.porcelainDeepBlue.opacity(0.72))
                Spacer()
                Button {
                    showCreateDream()
                } label: {
                    Image(systemName: "plus")
                        .font(.title2.weight(.black))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(Color.porcelainBlue, in: Circle())
                        .shadow(color: Color.porcelainBlue.opacity(0.20), radius: 14, y: 8)
                }
            }

            HStack(alignment: .bottom, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(copy("为了梦想", "For Dreams"))
                        .font(.system(size: 43, weight: .black, design: .rounded))
                        .foregroundStyle(Color.porcelainDeepBlue)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Text(copy("让心愿慢慢成器", "Let each wish take shape"))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.porcelainDeepBlue.opacity(0.58))
                }
                Spacer()
                Label(copy("青花瓷", "Porcelain Blue"), systemImage: "seal.fill")
                    .font(.caption.weight(.black))
                    .foregroundStyle(Color.porcelainBlue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.76), in: Capsule())
                    .overlay {
                        Capsule().stroke(Color.porcelainBlue.opacity(0.18), lineWidth: 1)
                    }
            }
        }
    }

    private func copy(_ chinese: String, _ english: String) -> String {
        AlbumCopy.pick(store.appLanguage, chinese, english)
    }

    private func updateDreamTitle(_ dream: Dream, title: String) {
        var copy = dream
        copy.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        store.update(copy)
    }

    private func showCreateDream() {
        if store.canCreateDream {
            isAddingDream = true
        } else {
            isShowingPremium = true
        }
    }

    private func moveDraggedDream(_ draggedID: UUID, before targetID: UUID) {
        guard draggedID != targetID else { return }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
            store.moveDream(draggedID, before: targetID)
        }
    }

    private func accent(for index: Int) -> CollageAccent {
        switch index % 4 {
        case 1: return .mint
        case 2: return .yellow
        case 3: return .blue
        default: return .pink
        }
    }
}

private struct CollageDreamDragDropModifier: ViewModifier {
    let dream: Dream
    @Binding var draggedDreamID: UUID?
    @Binding var dropTargetDreamID: UUID?
    var onMove: (UUID, UUID) -> Void

    func body(content: Content) -> some View {
        content
            .opacity(draggedDreamID == dream.id ? 0.72 : 1)
            .scaleEffect(dropTargetDreamID == dream.id ? 1.018 : 1)
            .overlay {
                if dropTargetDreamID == dream.id, draggedDreamID != dream.id {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color(red: 0.20, green: 0.47, blue: 1.0).opacity(0.78), lineWidth: 3)
                        .shadow(color: Color(red: 0.20, green: 0.47, blue: 1.0).opacity(0.25), radius: 10)
                        .allowsHitTesting(false)
                }
            }
            .onDrag {
                draggedDreamID = dream.id
                return NSItemProvider(object: dream.id.uuidString as NSString)
            }
            .onDrop(
                of: [UTType.text],
                delegate: CollageDreamDropDelegate(
                    targetID: dream.id,
                    draggedDreamID: $draggedDreamID,
                    dropTargetDreamID: $dropTargetDreamID,
                    onMove: onMove
                )
            )
    }
}

private struct CollageDreamDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var draggedDreamID: UUID?
    @Binding var dropTargetDreamID: UUID?
    var onMove: (UUID, UUID) -> Void

    func dropEntered(info: DropInfo) {
        guard draggedDreamID != targetID else { return }
        withAnimation(.easeOut(duration: 0.16)) {
            dropTargetDreamID = targetID
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        if let draggedDreamID, draggedDreamID != targetID {
            onMove(draggedDreamID, targetID)
        }
        self.draggedDreamID = nil
        dropTargetDreamID = nil
        return true
    }

    func dropExited(info: DropInfo) {
        if dropTargetDreamID == targetID {
            dropTargetDreamID = nil
        }
    }
}

private extension Text {
    func homeEyebrow() -> some View {
        font(.caption.weight(.black))
    }

    func homeTitle() -> some View {
        font(.system(size: 34, weight: .black, design: .serif))
            .lineSpacing(1)
    }

    func homeSectionTitle() -> some View {
        font(.system(size: 20, weight: .black, design: .serif))
    }

    func homeCaptionMeta() -> some View {
        font(.caption.weight(.bold))
    }

    func coverCTA() -> some View {
        font(.subheadline.weight(.bold))
    }
}

private struct EvidenceOverviewCard: View {
    @EnvironmentObject private var store: DreamStore

    private var evidenceCount: Int {
        store.activeDreams.reduce(0) { $0 + $1.evidenceCount }
    }

    private var imageCount: Int {
        store.activeDreams.reduce(0) { $0 + $1.imagePaths.count }
    }

    var body: some View {
        HStack(spacing: 10) {
            Label(copy("梦想画面墙", "Dream Wall"), systemImage: "photo.stack.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.albumGreen)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text("\(evidenceCount)")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(Color.albumInk)
            Text(copy("条记录", "records"))
                .homeCaptionMeta()
                .foregroundStyle(.secondary)
            Text("·")
                .foregroundStyle(.secondary)
            Text(copy("\(imageCount) 张画面", "\(imageCount) photos"))
                .homeCaptionMeta()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.5), lineWidth: 1)
        }
    }

    private func copy(_ chinese: String, _ english: String) -> String {
        AlbumCopy.pick(store.appLanguage, chinese, english)
    }
}

private struct CoverMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Text(label)
                .homeCaptionMeta()
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(minWidth: 42, alignment: .trailing)
    }
}

private struct CoverCTA: View {
    @EnvironmentObject private var store: DreamStore

    var body: some View {
        Label(copy("添加记录", "Add record"), systemImage: "plus")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.albumGreen.opacity(0.9), in: Capsule())
    }

    private func copy(_ chinese: String, _ english: String) -> String {
        AlbumCopy.pick(store.appLanguage, chinese, english)
    }
}

private struct CollageDreamWallHeader: View {
    @EnvironmentObject private var store: DreamStore
    let recordCount: Int
    let imageCount: Int

    var body: some View {
        HStack(spacing: 10) {
            Label(copy("梦想墙", "Dream Wall"), systemImage: "sparkles")
                .font(.subheadline.weight(.black))
                .foregroundStyle(Color.albumGreen)
            Spacer()
            Text(copy("\(recordCount) 条记录 · \(imageCount) 张画面", "\(recordCount) records · \(imageCount) photos"))
                .font(.caption.weight(.black))
                .foregroundStyle(Color.albumInk.opacity(0.62))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.white.opacity(0.54), in: Capsule())
        .overlay {
            Capsule().stroke(.white.opacity(0.62), lineWidth: 1)
        }
    }

    private func copy(_ chinese: String, _ english: String) -> String {
        AlbumCopy.pick(store.appLanguage, chinese, english)
    }
}

private struct CollageFeaturedDreamCard: View {
    @EnvironmentObject private var store: DreamStore
    let dream: Dream

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            MoodboardCollageView(paths: dream.imagePaths, cornerRadius: 30)
                .frame(height: 326)

            LinearGradient(
                colors: [.clear, .clear, .black.opacity(0.54)],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))

            CollageSticker(text: dream.evidenceCount == 0 ? copy("等待第一条记录", "First record") : copy("\(dream.evidenceCount) 条记录", "\(dream.evidenceCount) records"), symbol: "sparkles", tint: dream.evidenceCount == 0 ? Color.albumGreen : .white, fill: dream.evidenceCount == 0 ? Color.white.opacity(0.90) : Color.albumGreen.opacity(0.92))
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack(spacing: 12) {
                CollageSticker(text: copy("\(dream.imagePaths.count) 画面", "\(dream.imagePaths.count) photos"), symbol: "photo", tint: Color.albumInk.opacity(0.74), fill: Color.white.opacity(0.76))
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            VStack(alignment: .leading, spacing: 12) {
                Text(dream.title)
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                Text(dream.visionText.isEmpty ? copy("让梦想先有一张画面", "Give the dream a first image") : dream.visionText)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white.opacity(0.84))
                    .lineLimit(2)
                Label(copy("添加记录", "Add record"), systemImage: "plus")
                    .font(.headline.weight(.black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(Color.albumGreen.opacity(0.94), in: Capsule())
                    .padding(.top, 2)
            }
            .padding(20)
        }
        .frame(height: 326)
    }

    private func copy(_ chinese: String, _ english: String) -> String {
        AlbumCopy.pick(store.appLanguage, chinese, english)
    }
}

private struct CollageMiniDreamCard: View {
    @EnvironmentObject private var store: DreamStore
    let dream: Dream
    let rotation: Double

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            MoodboardCollageView(paths: dream.imagePaths, cornerRadius: 24, compact: true)
                .frame(height: 176)
            LinearGradient(colors: [.clear, .black.opacity(0.50)], startPoint: .top, endPoint: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            VStack(alignment: .leading, spacing: 8) {
                Text(dream.title)
                    .font(.system(size: 21, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.76)
                Text(dream.evidenceCount == 0 ? copy("等第一条记录", "First record") : copy("\(dream.evidenceCount) 条记录", "\(dream.evidenceCount) records"))
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white.opacity(0.82))
            }
            .padding(14)
        }
        .frame(height: 176)
        .rotationEffect(.degrees(rotation))
        .shadow(color: Color.albumInk.opacity(0.08), radius: 14, y: 8)
    }

    private func copy(_ chinese: String, _ english: String) -> String {
        AlbumCopy.pick(store.appLanguage, chinese, english)
    }
}

private struct CoverDreamImage: View {
    let path: String?
    let height: CGFloat

    var body: some View {
        GeometryReader { proxy in
            if let image = displayImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
            } else {
                DreamImage(path: nil, height: height)
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
}

private struct BeachFeaturedAlbumCard: View {
    @EnvironmentObject private var store: DreamStore
    let dream: Dream

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                CoverDreamImage(path: dream.imagePaths.first, height: 244)
                    .frame(height: 244)
                    .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))

                LinearGradient(
                    colors: [.black.opacity(0.16), .clear, .black.opacity(0.20)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))

                HStack {
                    BeachBadge(text: copy("主相册", "Featured"), symbol: "star.fill", tint: Color.beachCoral)
                    Spacer()
                    BeachBadge(text: copy("\(dream.imagePaths.count) 张画面", "\(dream.imagePaths.count) photos"), symbol: "photo", tint: Color.beachSeaBlue)
                }
                .padding(14)
            }

            VStack(alignment: .leading, spacing: 9) {
                Text(dream.title)
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(Color.albumInk)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                Text(dream.visionText.isEmpty ? copy("让梦想变具体，让未来在进行时", "Make dreams specific. Keep the future in motion.") : dream.visionText)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.albumInk.opacity(0.62))
                    .lineLimit(2)

                BeachWaveDivider(color: .beachSeaBlue)

                HStack {
                    Label(copy("添加记录", "Add record"), systemImage: "plus")
                        .font(.system(size: store.appLanguage == .english ? 13 : 15, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .padding(.horizontal, store.appLanguage == .english ? 14 : 18)
                        .padding(.vertical, 10)
                        .background(Color.beachCoral, in: Capsule())
                        .shadow(color: Color.beachCoral.opacity(0.20), radius: 8, y: 5)
                    Spacer()
                    Label(copy("拖动可置顶", "Drag to feature"), systemImage: "hand.draw.fill")
                        .font(.system(size: store.appLanguage == .english ? 10 : 11, weight: .black, design: .rounded))
                        .foregroundStyle(Color.beachSeaBlue.opacity(0.78))
                        .lineLimit(1)
                        .minimumScaleFactor(0.70)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 17)
        }
        .padding(8)
        .background(
            LinearGradient(colors: [Color.white.opacity(0.96), Color.beachSand.opacity(0.90)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 36, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .stroke(.white.opacity(0.82), lineWidth: 1)
        }
        .shadow(color: Color.beachSeaBlue.opacity(0.16), radius: 24, x: 0, y: 14)
    }

    private func copy(_ chinese: String, _ english: String) -> String {
        AlbumCopy.pick(store.appLanguage, chinese, english)
    }
}

private struct BeachAlbumMiniCard: View {
    @EnvironmentObject private var store: DreamStore
    let dream: Dream

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                ZStack(alignment: .top) {
                    CoverDreamImage(path: dream.imagePaths.first, height: proxy.size.height)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    LinearGradient(colors: [.black.opacity(0.14), .clear], startPoint: .top, endPoint: .center)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    HStack {
                        BeachBadge(text: "\(dream.imagePaths.count)", symbol: "photo", tint: Color.beachSeaBlue)
                        Spacer()
                        Image(systemName: "line.3.horizontal")
                            .font(.caption.weight(.black))
                            .foregroundStyle(.white.opacity(0.90))
                            .padding(7)
                            .background(.black.opacity(0.18), in: Circle())
                    }
                    .padding(9)
                }
            }
            .aspectRatio(4 / 3, contentMode: .fit)

            BeachWaveDivider(color: .beachSeaBlue)
                .frame(height: 12)

            VStack(alignment: .leading, spacing: 5) {
                Text(dream.title)
                    .font(.system(size: 19, weight: .black, design: .rounded))
                    .foregroundStyle(Color.albumInk)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                Text(copy("\(dream.evidenceCount) 条记录 · \(dream.imagePaths.count) 张画面", "\(dream.evidenceCount) records · \(dream.imagePaths.count) photos"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.albumInk.opacity(0.55))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .padding(.horizontal, 4)
        }
        .padding(10)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.94), Color.beachSand.opacity(0.84)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 25, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.80), lineWidth: 1)
        }
        .shadow(color: Color.beachSeaBlue.opacity(0.10), radius: 16, x: 0, y: 10)
    }

    private func copy(_ chinese: String, _ english: String) -> String {
        AlbumCopy.pick(store.appLanguage, chinese, english)
    }
}

private struct BeachBadge: View {
    let text: String
    let symbol: String
    let tint: Color

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.black))
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(.white.opacity(0.90), in: Capsule())
    }
}

private struct PorcelainFeaturedAlbumCard: View {
    @EnvironmentObject private var store: DreamStore
    let dream: Dream

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            CoverDreamImage(path: dream.imagePaths.first, height: 352)
                .frame(height: 352)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

            LinearGradient(
                colors: [.clear, .black.opacity(0.14), .black.opacity(0.68)],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

            VStack {
                HStack {
                    PorcelainKeyBorderStrip()
                        .stroke(.white.opacity(0.58), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                        .frame(width: 86, height: 18)
                    Spacer()
                    PorcelainKeyBorderStrip()
                        .stroke(.white.opacity(0.50), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                        .frame(width: 86, height: 18)
                        .rotationEffect(.degrees(180))
                }
                Spacer()
            }
            .padding(16)

            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    PorcelainBadge(text: copy("主相册", "Main"), symbol: "seal.fill")
                    Spacer()
                    PorcelainBadge(text: copy("\(dream.imagePaths.count) 张画面", "\(dream.imagePaths.count) photos"), symbol: "photo")
                }
                Spacer()
                Text(dream.title)
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                Text(dream.visionText.isEmpty ? copy("让梦想变具体，让未来在进行时", "Make dreams specific. Keep the future in motion.") : dream.visionText)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(2)
                HStack {
                    Label(copy("添加记录", "Add record"), systemImage: "plus")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(colors: [Color.porcelainBlue, Color.porcelainDeepBlue], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: Capsule()
                        )
                    Spacer()
                    Label(copy("拖动可置顶", "Drag to feature"), systemImage: "hand.draw.fill")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
            .padding(18)
        }
        .frame(height: 352)
        .padding(8)
        .background(
            LinearGradient(colors: [Color.porcelainWhite.opacity(0.98), Color.white.opacity(0.90), Color.porcelainMist.opacity(0.70)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 36, style: .continuous)
        )
        .overlay {
            PorcelainRimOverlay(cornerRadius: 36)
        }
        .shadow(color: Color.porcelainBlue.opacity(0.14), radius: 24, x: 0, y: 14)
    }

    private func copy(_ chinese: String, _ english: String) -> String {
        AlbumCopy.pick(store.appLanguage, chinese, english)
    }
}

private struct PorcelainMiniAlbumCard: View {
    @EnvironmentObject private var store: DreamStore
    let dream: Dream

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomLeading) {
                CoverDreamImage(path: dream.imagePaths.first, height: 142)
                    .frame(height: 142)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                LinearGradient(colors: [.clear, .black.opacity(0.58)], startPoint: .center, endPoint: .bottom)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                HStack {
                    PorcelainBadge(text: "\(dream.imagePaths.count)", symbol: "photo")
                    Spacer()
                    Image(systemName: "line.3.horizontal")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .padding(10)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(dream.title)
                    .font(.system(size: 21, weight: .black, design: .rounded))
                    .foregroundStyle(Color.porcelainDeepBlue)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                Text(copy("\(dream.evidenceCount) 条记录 · \(dream.imagePaths.count) 张画面", "\(dream.evidenceCount) records · \(dream.imagePaths.count) photos"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.porcelainDeepBlue.opacity(0.55))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .padding(.horizontal, 4)
        }
        .padding(10)
        .background(.white.opacity(0.86), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            PorcelainRimOverlay(cornerRadius: 26)
        }
        .shadow(color: Color.porcelainBlue.opacity(0.10), radius: 16, x: 0, y: 10)
    }

    private func copy(_ chinese: String, _ english: String) -> String {
        AlbumCopy.pick(store.appLanguage, chinese, english)
    }
}

private struct PorcelainBadge: View {
    let text: String
    let symbol: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.black))
            .foregroundStyle(Color.porcelainBlue)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(.white.opacity(0.92), in: Capsule())
            .overlay {
                Capsule().stroke(Color.porcelainBlue.opacity(0.22), lineWidth: 1)
            }
    }
}

private struct CollageFeaturedAlbumCard: View {
    @EnvironmentObject private var store: DreamStore
    let dream: Dream

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            CoverDreamImage(path: dream.imagePaths.first, height: 360)
                .frame(height: 360)
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))

            LinearGradient(
                colors: [.black.opacity(0.03), .black.opacity(0.08), .black.opacity(0.76)],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    CollageSticker(
                        text: copy("主相册", "Main"),
                        symbol: "star.fill",
                        tint: .white,
                        fill: Color.dopaminePink.opacity(0.94)
                    )
                    Spacer()
                    CollageSticker(
                        text: copy("\(dream.imagePaths.count) 张", "\(dream.imagePaths.count) photos"),
                        symbol: "photo",
                        tint: Color.albumInk,
                        fill: .white.opacity(0.92)
                    )
                }
                Spacer()
                Text(dream.title)
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)

                Text(dream.visionText.isEmpty ? copy("让梦想先有一张画面", "Give the dream a first image") : dream.visionText)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(2)

                HStack {
                    ButtonLikeCTA(title: copy("添加记录", "Add record"), isCompact: true)
                    Spacer()
                    Label(copy("拖动可置顶", "Drag to feature"), systemImage: "hand.draw.fill")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(.white.opacity(0.70))
                }
            }
            .padding(18)
        }
        .frame(height: 360)
        .background(.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(.white.opacity(0.78), lineWidth: 4)
        }
        .shadow(color: Color.dopamineBlue.opacity(0.16), radius: 24, x: 0, y: 14)
    }

    private func copy(_ chinese: String, _ english: String) -> String {
        AlbumCopy.pick(store.appLanguage, chinese, english)
    }
}

private struct CollageAlbumMiniCard: View {
    @EnvironmentObject private var store: DreamStore
    let dream: Dream
    let accent: CollageAccent

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            CoverDreamImage(path: dream.imagePaths.first, height: 194)
                .frame(height: 194)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            LinearGradient(
                colors: [.clear, .black.opacity(0.70)],
                startPoint: .center,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    CollageSticker(
                        text: "\(dream.imagePaths.count)",
                        symbol: "photo",
                        tint: Color.albumInk,
                        fill: .white.opacity(0.90)
                    )
                    Spacer()
                    Image(systemName: "line.3.horizontal")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white.opacity(0.70))
                }
                Spacer()
                Text(dream.title)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)

                HStack(spacing: 7) {
                    Label("\(dream.evidenceCount)", systemImage: "pencil")
                    Text("·")
                    Label("\(dream.activeStageCount)", systemImage: "flag.fill")
                }
                .font(.caption2.weight(.black))
                .foregroundStyle(.white.opacity(0.74))
            }
            .padding(12)
        }
        .frame(height: 194)
        .background(.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(.white.opacity(0.78), lineWidth: 3)
        }
        .shadow(color: accent.color.opacity(0.16), radius: 16, x: 0, y: 10)
    }

    private func copy(_ chinese: String, _ english: String) -> String {
        AlbumCopy.pick(store.appLanguage, chinese, english)
    }
}

private enum CollageAccent {
    case pink, mint, yellow, blue

    var color: Color {
        switch self {
        case .pink: return Color(red: 1.0, green: 0.36, blue: 0.46)
        case .mint: return Color(red: 0.45, green: 0.86, blue: 0.62)
        case .yellow: return Color(red: 1.0, green: 0.82, blue: 0.25)
        case .blue: return Color(red: 0.28, green: 0.50, blue: 1.0)
        }
    }

    var stickerText: String {
        switch self {
        case .pink: return "主推"
        case .mint: return "自由一夏"
        case .yellow: return "节奏自由"
        case .blue: return "正在生长"
        }
    }

    var symbol: String {
        switch self {
        case .pink: return "star.fill"
        case .mint: return "figure.pool.swim"
        case .yellow: return "bolt.fill"
        case .blue: return "sparkles"
        }
    }
}

private struct CollagePolaroidDreamCard: View {
    @EnvironmentObject private var store: DreamStore
    let dream: Dream
    let accent: CollageAccent
    var isFeatured = false

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    DreamImage(path: dream.imagePaths.first, height: imageHeight(in: size))
                        .frame(height: imageHeight(in: size))
                        .clipShape(RoundedRectangle(cornerRadius: isFeatured ? 18 : 14, style: .continuous))

                    if isFeatured {
                        Label(copy("主推", "Featured"), systemImage: "star.fill")
                            .font(.caption.weight(.black))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(accent.color, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .offset(x: -4, y: -4)
                    }

                    Label("\(dream.imagePaths.count)", systemImage: "photo")
                        .font(.caption.weight(.black))
                        .foregroundStyle(Color.albumInk)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .frame(maxWidth: .infinity, alignment: .topTrailing)
                        .padding(9)
                }
                .padding(isFeatured ? 14 : 10)
                .padding(.bottom, isFeatured ? 0 : 2)

                VStack(alignment: .leading, spacing: isFeatured ? 8 : 7) {
                    Text(dream.title)
                        .font(AlbumFonts.collageTitle(isFeatured ? 36 : 27))
                        .foregroundStyle(Color.albumInk)
                        .lineLimit(2)
                        .minimumScaleFactor(0.70)
                        .overlay(alignment: .bottomLeading) {
                            SketchStroke(color: accent.color.opacity(0.42))
                                .frame(width: min(size.width * 0.68, isFeatured ? 190 : 120), height: isFeatured ? 12 : 8)
                                .offset(y: isFeatured ? 4 : 3)
                        }

                    if isFeatured {
                        ButtonLikeCTA(title: copy("添加记录", "Add record"), isCompact: size.width < 230)
                    } else {
                        HStack(spacing: 12) {
                            Label("\(dream.evidenceCount) 条记录", systemImage: "shoeprints.fill")
                            Label("\(dream.activeStageCount) 个下一步", systemImage: "calendar")
                        }
                        .font(.caption2.weight(.black))
                        .foregroundStyle(Color.albumInk.opacity(0.58))
                    }
                }
                .padding(.horizontal, isFeatured ? 18 : 12)
                .padding(.bottom, isFeatured ? 16 : 14)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .background(.white.opacity(0.96), in: RoundedRectangle(cornerRadius: isFeatured ? 22 : 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: isFeatured ? 22 : 18, style: .continuous)
                    .stroke(.white, lineWidth: 1)
            }
            .overlay(alignment: isFeatured ? .trailing : .bottomTrailing) {
                StampSticker(text: accent.stickerText, symbol: accent.symbol, color: accent.color, large: isFeatured)
                    .offset(x: isFeatured ? 18 : 16, y: isFeatured ? -22 : 12)
                    .rotationEffect(.degrees(isFeatured ? -10 : 12))
            }
            .overlay(alignment: .top) {
                CollageTape(color: accent == .mint ? Color(red: 0.62, green: 0.92, blue: 0.52).opacity(0.62) : Color.softGold.opacity(0.54), rotation: isFeatured ? -4 : 5)
                    .offset(y: -13)
            }
            .shadow(color: Color.albumInk.opacity(0.13), radius: isFeatured ? 18 : 13, x: 0, y: isFeatured ? 14 : 9)
        }
    }

    private func imageHeight(in size: CGSize) -> CGFloat {
        isFeatured ? size.height * 0.54 : size.height * 0.48
    }

    private func copy(_ chinese: String, _ english: String) -> String {
        AlbumCopy.pick(store.appLanguage, chinese, english)
    }
}

private struct ButtonLikeCTA: View {
    let title: String
    var isCompact = false

    var body: some View {
        Label(title, systemImage: "plus")
            .font(.system(size: isCompact ? 15 : 17, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, isCompact ? 18 : 24)
            .padding(.vertical, isCompact ? 10 : 12)
            .background(
                LinearGradient(
                    colors: [Color.dopamineBlue, Color(red: 0.05, green: 0.62, blue: 1.0)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: Capsule()
            )
            .shadow(color: Color(red: 0.20, green: 0.38, blue: 0.92).opacity(0.24), radius: 10, y: 6)
    }
}

private struct StampSticker: View {
    let text: String
    let symbol: String
    let color: Color
    var large = false

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: large ? 18 : 13, weight: .black))
            Text(text)
                .font(.system(size: large ? 13 : 10, weight: .black, design: .rounded))
                .lineLimit(2)
                .minimumScaleFactor(0.72)
        }
        .foregroundStyle(Color.albumInk)
        .multilineTextAlignment(.center)
        .padding(large ? 13 : 9)
        .frame(width: large ? 82 : 58, height: large ? 82 : 58)
        .background(color.opacity(large ? 0.82 : 0.72), in: Circle())
        .overlay {
            Circle().stroke(.white.opacity(0.72), lineWidth: 1)
        }
        .shadow(color: Color.albumInk.opacity(0.12), radius: 8, y: 5)
    }
}

private struct CollageWallTitle: View {
    @EnvironmentObject private var store: DreamStore

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 3) {
                Text(copy("梦想画面墙", "Dream Vision Wall"))
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(Color.albumInk)
            }
            Spacer()
        }
    }

    private func copy(_ chinese: String, _ english: String) -> String {
        AlbumCopy.pick(store.appLanguage, chinese, english)
    }
}

private struct BeachWallTitle: View {
    @EnvironmentObject private var store: DreamStore

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 5) {
                Text(copy("梦想画面墙", "Dream Vision Wall"))
                    .font(.system(size: store.appLanguage == .english ? 26 : 30, weight: .black, design: .rounded))
                    .foregroundStyle(Color.albumInk)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(copy("让梦想变具体，让未来在进行时", "Make dreams specific. Keep the future in motion."))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.albumInk.opacity(0.55))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Text(copy("\(store.activeDreams.count) 本", "\(store.activeDreams.count) albums"))
                .font(.caption.weight(.black))
                .foregroundStyle(Color.beachSeaBlue)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.white.opacity(0.68), in: Capsule())
        }
    }

    private func copy(_ chinese: String, _ english: String) -> String {
        AlbumCopy.pick(store.appLanguage, chinese, english)
    }
}

private struct PorcelainWallTitle: View {
    @EnvironmentObject private var store: DreamStore

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 5) {
                Text(copy("梦想画面墙", "Dream Vision Wall"))
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(Color.porcelainDeepBlue)
                Text(copy("让梦想变具体，让未来在进行时", "Make dreams specific. Keep the future in motion."))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.porcelainDeepBlue.opacity(0.55))
            }
            Spacer()
            Text(copy("\(store.activeDreams.count) 本", "\(store.activeDreams.count) albums"))
                .font(.caption.weight(.black))
                .foregroundStyle(Color.porcelainBlue)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.white.opacity(0.72), in: Capsule())
                .overlay {
                    Capsule().stroke(Color.porcelainBlue.opacity(0.16), lineWidth: 1)
                }
        }
        .overlay(alignment: .bottomLeading) {
            PorcelainKeyBorderStrip()
                .stroke(Color.porcelainBlue.opacity(0.22), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .frame(width: 132, height: 24)
                .offset(y: 14)
        }
    }

    private func copy(_ chinese: String, _ english: String) -> String {
        AlbumCopy.pick(store.appLanguage, chinese, english)
    }
}

private struct CollageActionStrip: View {
    @EnvironmentObject private var store: DreamStore

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.25, green: 0.50, blue: 1.0), Color(red: 0.42, green: 0.54, blue: 1.0)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "camera.fill")
                    .font(.headline.weight(.black))
                    .foregroundStyle(.white)
            }
            .frame(width: 44, height: 44)
            Text(copy("记录当下的行动，未来感谢现在的你", "Record today's action. Future you will thank you."))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.albumInk.opacity(0.76))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Spacer()
            Image(systemName: "chevron.right.circle")
                .font(.title3.weight(.bold))
                .foregroundStyle(Color(red: 0.28, green: 0.50, blue: 1.0))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.white.opacity(0.46), in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color(red: 0.32, green: 0.52, blue: 1.0).opacity(0.50), style: StrokeStyle(lineWidth: 1.4, dash: [4, 4]))
        }
        .padding(.top, -4)
    }

    private func copy(_ chinese: String, _ english: String) -> String {
        AlbumCopy.pick(store.appLanguage, chinese, english)
    }
}

private struct TornNoteCard: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(Color.albumInk)
            .lineSpacing(5)
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
            .background {
                TornPaperShape()
                    .fill(Color(red: 1.0, green: 0.985, blue: 0.94).opacity(0.94))
                    .shadow(color: Color.albumInk.opacity(0.11), radius: 10, y: 6)
            }
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color(red: 0.44, green: 0.63, blue: 0.92).opacity(0.54))
                    .frame(width: 92, height: 18)
                    .rotationEffect(.degrees(-2))
                    .offset(y: -10)
            }
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "heart")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color(red: 1.0, green: 0.42, blue: 0.50).opacity(0.76))
                    .offset(x: -10, y: -9)
            }
    }
}

private struct DraggableHomeNote: View {
    let text: String
    @AppStorage("dream_album.home_note_offset_x") private var storedOffsetX = 0.0
    @AppStorage("dream_album.home_note_offset_y") private var storedOffsetY = 0.0
    @GestureState private var dragTranslation: CGSize = .zero

    private var currentOffset: CGSize {
        CGSize(
            width: storedOffsetX + dragTranslation.width,
            height: storedOffsetY + dragTranslation.height
        )
    }

    var body: some View {
        TornNoteCard(text: text)
            .offset(currentOffset)
            .gesture(
                DragGesture(minimumDistance: 2)
                    .updating($dragTranslation) { value, state, _ in
                        state = value.translation
                    }
                    .onEnded { value in
                        storedOffsetX += value.translation.width
                        storedOffsetY += value.translation.height
                    }
            )
            .onTapGesture(count: 2) {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                    storedOffsetX = 0
                    storedOffsetY = 0
                }
            }
            .accessibilityHint("拖动可以调整便签位置，双击恢复默认位置")
    }
}

private struct AppLogoMark: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.08, green: 0.58, blue: 1.0), Color(red: 0.16, green: 0.38, blue: 1.0)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text("d")
                .font(.system(size: size * 0.72, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .offset(x: -1, y: -2)
        }
        .frame(width: size, height: size)
        .shadow(color: Color(red: 0.05, green: 0.42, blue: 1.0).opacity(0.22), radius: 10, y: 6)
    }
}

private struct SketchStroke: View {
    var color: Color

    var body: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: CGPoint(x: 2, y: size.height * 0.58))
            path.addCurve(
                to: CGPoint(x: size.width - 2, y: size.height * 0.48),
                control1: CGPoint(x: size.width * 0.28, y: size.height * 0.12),
                control2: CGPoint(x: size.width * 0.58, y: size.height * 0.92)
            )
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: max(size.height * 0.34, 3), lineCap: .round, lineJoin: .round))
        }
    }
}

private struct TornPaperShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 8, y: rect.minY + 5))
        path.addLine(to: CGPoint(x: rect.maxX - 12, y: rect.minY + 2))
        path.addLine(to: CGPoint(x: rect.maxX - 5, y: rect.minY + rect.height * 0.36))
        path.addLine(to: CGPoint(x: rect.maxX - 10, y: rect.maxY - 9))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.78, y: rect.maxY - 4))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.60, y: rect.maxY - 10))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.maxY - 3))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.22, y: rect.maxY - 8))
        path.addLine(to: CGPoint(x: rect.minX + 4, y: rect.maxY - 5))
        path.addLine(to: CGPoint(x: rect.minX + 2, y: rect.minY + rect.height * 0.28))
        path.closeSubpath()
        return path
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private struct FeaturedDreamCard: View {
    @EnvironmentObject private var store: DreamStore
    let dream: Dream

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            MagazineCollageView(paths: dream.imagePaths, cornerRadius: 28, showCountBadge: true)
                .frame(height: 390)

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    statusBadge
                    Spacer()
                    HStack(spacing: 14) {
                        if dream.evidenceCount == 0 {
                            CoverMetric(value: "新", label: "相册")
                        } else {
                            CoverMetric(value: "\(dream.evidenceCount)", label: "记录")
                        }
                        CoverMetric(value: "\(dream.imagePaths.count)", label: "画面")
                        if dream.activeStageCount > 0 {
                            CoverMetric(value: "\(dream.activeStageCount)", label: "下一步")
                        }
                    }
                }

                Spacer()

                VStack(alignment: .leading, spacing: 12) {
                    Text("FEATURED")
                        .homeEyebrow()
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.66))
                    Text(dream.title)
                        .font(.system(size: 36, weight: .black, design: .serif))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.76)
                    Text(dream.visionText.isEmpty ? copy("把梦想描述变清楚", "Make the vision clearer") : dream.visionText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .opacity(0.82)
                    CoverCTA()
                        .padding(.top, 2)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [.black.opacity(0.12), .clear, .black.opacity(0.74)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            )
        }
        .frame(height: 390)
    }

    private var statusBadge: some View {
        Text(dream.evidenceCount == 0 ? copy("等待第一条记录", "First record waiting") : copy("\(dream.evidenceCount) 条记录", "\(dream.evidenceCount) records"))
            .homeCaptionMeta()
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(dream.evidenceCount == 0 ? Color.albumPaper.opacity(0.92) : Color.albumGreen.opacity(0.9), in: Capsule())
            .foregroundStyle(dream.evidenceCount == 0 ? Color.albumGreen : .white)
    }

    private func copy(_ chinese: String, _ english: String) -> String {
        AlbumCopy.pick(store.appLanguage, chinese, english)
    }
}

private struct SectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            Text(title)
                .homeSectionTitle()
                .foregroundStyle(Color.albumInk)
            Spacer()
            Text(subtitle)
                .homeCaptionMeta()
                .foregroundStyle(.secondary)
        }
    }
}

private struct DreamGridCard: View {
    @EnvironmentObject private var store: DreamStore
    let dream: Dream

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                HomeAlbumCoverView(paths: dream.imagePaths, cornerRadius: 20, overlayScale: 0.34)
                    .frame(width: proxy.size.width, height: 262)

                LinearGradient(
                    colors: [.clear, .black.opacity(0.18), .black.opacity(0.72)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text(dream.evidenceCount == 0 ? copy("等第一条记录", "First record") : copy("\(dream.evidenceCount) 条记录", "\(dream.evidenceCount) records"))
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(dream.evidenceCount == 0 ? Color.white.opacity(0.88) : Color.albumGreen.opacity(0.9), in: Capsule())
                            .foregroundStyle(dream.evidenceCount == 0 ? Color.albumGreen : .white)
                        Spacer()
                    }

                    Text(dream.title)
                        .font(.system(size: 23, weight: .black, design: .serif))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    HStack(spacing: 10) {
                        Label(copy("\(dream.imagePaths.count) 张画面", "\(dream.imagePaths.count) photos"), systemImage: "photo.on.rectangle")
                        Label(copy("\(dream.evidenceCount) 条记录", "\(dream.evidenceCount) records"), systemImage: "sparkles")
                        if dream.activeStageCount > 0 {
                            Label(copy("\(dream.activeStageCount) 个下一步", "\(dream.activeStageCount) next"), systemImage: "flag.fill")
                        }
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.82))
                }
                .padding(14)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 12, y: 6)
        }
        .frame(width: 218, height: 262)
    }

    private func copy(_ chinese: String, _ english: String) -> String {
        AlbumCopy.pick(store.appLanguage, chinese, english)
    }
}

private struct DreamSquareCard: View {
    @EnvironmentObject private var store: DreamStore
    let dream: Dream

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            HomeAlbumCoverView(paths: dream.imagePaths, cornerRadius: 20, overlayScale: 0.38)
                .aspectRatio(1, contentMode: .fit)
            LinearGradient(colors: [.clear, .black.opacity(0.68)], startPoint: .top, endPoint: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            VStack(alignment: .leading, spacing: 7) {
                Text(dream.title)
                    .font(.system(size: 20, weight: .black, design: .serif))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(dream.visionText.isEmpty ? copy("让画面更清楚", "Clarify the vision") : dream.visionText)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.76))
            }
            .padding(13)
        }
    }

    private func copy(_ chinese: String, _ english: String) -> String {
        AlbumCopy.pick(store.appLanguage, chinese, english)
    }
}

private struct DreamTimelineCard: View {
    @EnvironmentObject private var store: DreamStore
    let dream: Dream

    var body: some View {
        HStack(spacing: 14) {
            HomeAlbumCoverView(paths: dream.imagePaths, cornerRadius: 18, overlayScale: 0.44)
                .frame(width: 104, height: 104)
                .shadow(color: .black.opacity(0.08), radius: 10, y: 5)
            VStack(alignment: .leading, spacing: 8) {
                Text(dream.title)
                    .font(.system(size: 22, weight: .black, design: .serif))
                    .foregroundStyle(Color.albumInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Text(dream.latestLog?.action ?? (dream.visionText.isEmpty ? copy("还没有成长记录，先让梦想有画面。", "No records yet. Start with a clear vision.") : dream.visionText))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 10) {
                    Label(copy("\(dream.evidenceCount) 条记录", "\(dream.evidenceCount) records"), systemImage: "sparkles")
                    Label(copy("\(dream.imagePaths.count) 张", "\(dream.imagePaths.count) photos"), systemImage: "photo")
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.albumGreen)
            }
            .layoutPriority(1)
            Spacer()
        }
        .padding(12)
        .background(.white.opacity(0.66), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func copy(_ chinese: String, _ english: String) -> String {
        AlbumCopy.pick(store.appLanguage, chinese, english)
    }
}

private struct EmptyDreamState: View {
    @EnvironmentObject private var store: DreamStore

    var body: some View {
        Group {
            if store.settingsDisplayStyle == .beach {
                beachEmptyState
            } else {
                defaultEmptyState
            }
        }
    }

    private var defaultEmptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(Color.albumGreen)
            Text(copy("还没有梦想相册", "No dream albums yet"))
                .font(.title3.bold())
            Text(copy("点击右上角 + 创建第一本相册", "Tap + in the corner to create one"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 70)
        .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var beachEmptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                BeachWaveBand(amplitude: 7, phase: 0.18)
                    .fill(Color.beachSeaBlue.opacity(0.18))
                    .frame(width: 150, height: 54)
                    .offset(y: 30)
                BeachStarfishMark()
                    .fill(Color.beachCoral.opacity(0.78))
                    .frame(width: 38, height: 38)
                    .offset(x: -42, y: 16)
                BeachShellMark()
                    .fill(Color.beachShellPink.opacity(0.82))
                    .frame(width: 46, height: 40)
                    .rotationEffect(.degrees(-12))
                    .offset(x: 34, y: 8)
                BeachFootprints()
                    .fill(Color.softGold.opacity(0.34))
                    .frame(width: 32, height: 58)
                    .rotationEffect(.degrees(14))
                    .offset(x: 2, y: -18)
            }
            .frame(height: 92)

            Text(copy("从第一张梦想画面开始", "Start with your first dream photo"))
                .font(.system(size: 23, weight: .black, design: .rounded))
                .foregroundStyle(Color.albumInk)
                .multilineTextAlignment(.center)
            Text(copy("点击右上角 +，把想去的地方、想成为的样子留进相册。", "Tap + and save the places you want to go and the person you want to become."))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.albumInk.opacity(0.58))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 44)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.92), Color.beachSand.opacity(0.82)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.88), lineWidth: 1.5)
        }
        .shadow(color: Color.beachSeaBlue.opacity(0.10), radius: 18, y: 10)
    }

    private func copy(_ chinese: String, _ english: String) -> String {
        AlbumCopy.pick(store.appLanguage, chinese, english)
    }
}

struct NewDreamSheet: View {
    @Environment(\.albumTheme) private var theme
    @EnvironmentObject private var store: DreamStore
    @EnvironmentObject private var purchaseStore: PurchaseStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var visionText = ""
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var imagePaths: [String] = []
    @State private var isShowingPremium = false
    @State private var isShowingCamera = false
    @State private var isShowingPhotoLibrary = false

    var body: some View {
        NavigationStack {
            Form {
                if !store.canCreateDream {
                    Section {
                        Button {
                            isShowingPremium = true
                        } label: {
                            Label(copy("解锁不限量梦想相册", "Unlock unlimited dream albums"), systemImage: "lock.open.fill")
                        }
                    } footer: {
                        Text(copy("免费版最多保留 \(DreamStore.freeActiveDreamLimit) 本活跃相册。", "The free version supports up to \(DreamStore.freeActiveDreamLimit) active albums."))
                    }
                }

                Section(copy("选择照片", "Photos")) {
                    PhotoSourceMenu(showingLibrary: $isShowingPhotoLibrary, showingCamera: $isShowingCamera, identifier: "dream.new.addPhotos")
                    .photosPicker(isPresented: $isShowingPhotoLibrary, selection: $selectedItems, matching: .images)
                    .onChange(of: selectedItems) { _, newItems in
                        Task { await importImages(from: newItems) }
                    }

                    if !imagePaths.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(imagePaths, id: \.self) { path in
                                    DreamImage(path: path, height: 86)
                                        .frame(width: 86)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        Text(copy("已选择 \(imagePaths.count) 张画面", "\(imagePaths.count) photos selected"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(copy("选择照片，创建画册。", "Choose photos to create an album."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section(copy("名称", "Name")) {
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

                Section(copy("描述", "Description")) {
                    TextEditor(text: $visionText)
                        .frame(minHeight: 92)
                        .onChange(of: visionText) { _, newValue in
                            if newValue.count > 120 {
                                visionText = String(newValue.prefix(120))
                            }
                        }
                    Text(copy("比如：我站在终点，手里拿着奖牌，知道自己真的做到了。", "e.g. I cross the finish line, holding the medal, knowing I really did it."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(visionText.count)/120")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AlbumBackground())
            .navigationTitle(copy("创建梦想相册", "Create Dream Album"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(copy("取消", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(copy("创建", "Create")) {
                        guard store.canCreateDream else {
                            isShowingPremium = true
                            return
                        }
                        store.addDream(
                            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                            visionText: visionText.trimmingCharacters(in: .whitespacesAndNewlines),
                            imagePaths: imagePaths
                        )
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .sheet(isPresented: $isShowingPremium) {
                PremiumUnlockSheet()
                    .environmentObject(store)
                    .environmentObject(purchaseStore)
                    .presentationDetents([.medium, .large])
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
            if !imagePaths.contains(path) {
                imagePaths.append(path)
            }
        }
    }

    private func saveCapturedImage(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.92),
              let path = try? ImageLibrary.saveImageData(data),
              !imagePaths.contains(path) else { return }
        imagePaths.append(path)
    }

    private func copy(_ chinese: String, _ english: String) -> String {
        AlbumCopy.pick(store.appLanguage, chinese, english)
    }
}
