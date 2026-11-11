import SwiftUI

struct CollageGridEditor: View {
    @ObservedObject var model: CollageEditorModel
    @EnvironmentObject private var store: DreamStore
    @Environment(\.albumTheme) private var theme
    let addPhotos: (Bool) -> Void
    let showLayers: () -> Void
    let showAdvanced: () -> Void
    @State private var tool = GridTool.templates
    @State private var exchange: UUID?
    @State private var crop: CollageGridCrop?
    private var c: (String, String) -> String { { AlbumCopy.pick(store.appLanguage, $0, $1) } }
    private var photos: [CollageLayer] { model.document.layers.filter(\.isPhoto) }

    var body: some View {
        GeometryReader { viewport in
            let wide = viewport.size.width >= 750
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    CollageGridCanvas(model: model, exchange: exchange, select: select, crop: openCrop)
                    if !wide { controls(height: viewport.size.height < 580 ? 150 : 200) }
                }
                if wide { controls(height: nil).frame(width: 300).background(theme.surface) }
            }
        }
        .sheet(item: $crop) { value in
            NavigationStack {
                CollageGridCropView(crop: value, image: model.gridImages[value.id], document: model.document) { result in
                    model.commitGridCrop(result)
                }
            }.presentationDetents([.large])
        }
        .onChange(of: model.document) { _, doc in
            if let exchange, !doc.layers.contains(where: { $0.id == exchange && !$0.locked }) { self.exchange = nil }
            if let selection = model.selection, !doc.layers.contains(where: { $0.id == selection }) { model.selection = nil }
        }
        .onChange(of: model.selection) { _, selection in if selection == nil { exchange = nil } }
    }

    private func controls(height: CGFloat?) -> some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Text(exchange != nil ? c("点选另一张照片", "Choose another photo") : panelTitle).font(.subheadline.weight(.semibold))
                Spacer()
                if exchange != nil {
                    Button(c("取消", "Cancel")) { exchange = nil }.accessibilityIdentifier("grid.swap.cancel")
                } else {
                    Menu {
                        Button(c("添加文字", "Add text"), systemImage: "textformat") {
                            let layer = CollageLayer(text: c("写点什么", "Your text"), x: 0.1, y: 0.4, width: 0.8, height: 0.2)
                            model.apply { $0.layers.append(layer) }; model.selection = layer.id; showAdvanced()
                        }.disabled(model.document.layers.filter { !$0.isPhoto }.count >= 10)
                        Button(c("图层与锁定", "Layers & locks"), systemImage: "square.3.layers.3d", action: showLayers)
                        Button(c("更多设置", "More settings"), systemImage: "slider.horizontal.3", action: showAdvanced)
                    } label: { Image(systemName: "ellipsis").frame(width: 44, height: 32) }
                        .accessibilityLabel(c("更多设置", "More settings")).accessibilityIdentifier("grid.more")
                }
            }.padding(.horizontal, 16).padding(.top, 8)
            ScrollView(.vertical) {
                Group {
                    if model.selected != nil || tool == .photos { photoPanel }
                    else {
                        switch tool {
                        case .templates: templatePanel(wide: height == nil)
                        case .ratio: ratioPanel
                        case .style: stylePanel
                        case .photos: photoPanel
                        }
                    }
                }.padding(.horizontal, 16).padding(.bottom, 10)
            }.frame(height: height)
            HStack(spacing: 0) {
                ForEach(GridTool.allCases) { item in
                    Button {
                        model.endGesture(); exchange = nil; model.selection = nil; tool = item
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: item.icon).font(.system(size: 20))
                            Text(item.title(store.appLanguage)).font(.caption.weight(tool == item ? .semibold : .regular))
                        }.frame(maxWidth: .infinity, minHeight: 54).contentShape(Rectangle())
                            .foregroundStyle(tool == item ? theme.accent : theme.secondary)
                            .background(tool == item ? theme.accent.opacity(0.09) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain).accessibilityAddTraits(tool == item ? .isSelected : [])
                        .accessibilityIdentifier("grid.tool." + item.rawValue)
                }
            }.padding(.horizontal, 12).padding(.vertical, 6)
        }.background(theme.utilityBackground)
    }
    private var panelTitle: String {
        if let layer = model.selected { return layer.isPhoto ? c("照片 \((photos.firstIndex { $0.id == layer.id } ?? 0)+1)", "Photo \((photos.firstIndex { $0.id == layer.id } ?? 0)+1)") : c("文字", "Text") }
        return tool.title(store.appLanguage)
    }
    @ViewBuilder private func templatePanel(wide: Bool) -> some View {
        if wide {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) { templateTiles }.padding(.vertical, 8)
        } else {
            ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 12) { templateTiles }.padding(.vertical, 8) }
        }
    }
    @ViewBuilder private var templateTiles: some View {
                if model.document.gridTemplateID == nil {
                    templateTile(model.document, name: c("原排版", "Original"), selected: true, id: "legacy", action: {})
                }
                ForEach(CollageGridTemplate.available(for: photos.count)) { template in
                    let document = templateDocument(template)
                    templateTile(document, name: template.title(store.appLanguage, count: photos.count), selected: model.document.gridTemplateID == template.rawValue, id: template.rawValue) {
                        model.apply { $0.gridTemplateID = template.rawValue }
                    }
                }
    }
    private func templateDocument(_ template: CollageGridTemplate) -> CollageDocument {
        var doc = model.document; doc.gridTemplateID = template.rawValue; return doc
    }
    private func templateTile(_ doc: CollageDocument, name: String, selected: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                GridMiniature(document: doc, images: model.gridImages)
                    .frame(width: 90, height: 88).padding(4)
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(selected ? theme.accent : theme.secondary.opacity(0.2), lineWidth: selected ? 2 : 1))
                    .overlay(alignment: .topTrailing) {
                        if selected { Image(systemName: "checkmark.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.white, theme.accent).padding(2) }
                    }
                Text(name).font(.caption).lineLimit(1)
            }.foregroundStyle(selected ? theme.accent : theme.primary)
        }.buttonStyle(.plain).accessibilityLabel(name).accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("grid.template." + id)
    }
    private var ratioPanel: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72))], spacing: 10) {
            ForEach(CollageRatio.allCases) { ratio in
                Button { model.apply { $0.ratio = ratio } } label: {
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 3).stroke(lineWidth: 1.5)
                            .frame(width: ratio.value >= 1 ? 30 : 30*ratio.value, height: ratio.value >= 1 ? 30/ratio.value : 30)
                        Text(ratio.rawValue).font(.caption)
                    }.frame(maxWidth: .infinity, minHeight: 64)
                        .foregroundStyle(model.document.ratio == ratio ? theme.accent : theme.primary)
                        .background(theme.surface, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(model.document.ratio == ratio ? theme.accent : .clear, lineWidth: 2))
                }.buttonStyle(.plain).accessibilityAddTraits(model.document.ratio == ratio ? .isSelected : [])
                    .accessibilityIdentifier("grid.ratio."+ratio.rawValue)
            }
        }.padding(.top, 8)
    }
    private var stylePanel: some View {
        VStack(spacing: 8) {
            styleSlider(c("间距", "Spacing"), \.spacing, 0...0.06, id: "spacing")
            styleSlider(c("外边距", "Margin"), \.margin, 0...0.12, id: "margin")
            styleSlider(c("圆角", "Corners"), \.corner, 0...0.2, id: "corner")
            ColorPicker(c("背景", "Background"), selection: Binding(get: { Color(uiColor: CollageRenderer.color(model.document.background)) }, set: { color in
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
                model.apply { $0.background = String(format: "%02X%02X%02X", Int(r*255), Int(g*255), Int(b*255)) }
            }), supportsOpacity: false).font(.subheadline)
        }.padding(.top, 4)
    }
    private func styleSlider(_ label: String, _ key: WritableKeyPath<CollageDocument, Double>, _ range: ClosedRange<Double>, id: String) -> some View {
        HStack {
            Text(label).font(.caption).frame(width: 64, alignment: .leading)
            Slider(value: Binding(get: { model.document[keyPath: key] }, set: { value in
                model.beginGesture(); model.document[keyPath: key] = value
            }), in: range, onEditingChanged: { active in if !active { model.endGesture() } })
                .accessibilityLabel(label).accessibilityIdentifier("grid.style."+id)
        }
    }
    private var photoPanel: some View {
        VStack(spacing: 10) {
            if let selected = model.selected {
                if selected.isPhoto {
                    HStack(spacing: 0) {
                        photoAction("crop", c("裁切", "Crop"), id: "crop") { openCrop(selected.id) }.disabled(selected.locked)
                        photoAction("arrow.triangle.2.circlepath", c("替换", "Replace"), id: "replace") { addPhotos(true) }.disabled(selected.locked)
                        photoAction("arrow.left.arrow.right", c("交换", "Swap"), id: "swap") { exchange = selected.id }.disabled(selected.locked || photos.filter { !$0.locked }.count < 2)
                        photoAction("trash", c("移除", "Remove"), id: "remove") { model.removeGridPhoto(selected.id) }.disabled(selected.locked || photos.count <= 2)
                    }
                } else { Button(c("编辑文字", "Edit text"), action: showAdvanced) }
                if selected.locked { Label(c("已锁定", "Locked"), systemImage: "lock.fill").font(.caption).foregroundStyle(theme.secondary) }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(photos.enumerated()), id: \.element.id) { index, layer in
                        Button { select(layer.id) } label: {
                            ZStack(alignment: .bottomTrailing) {
                                if let image = model.gridImages[layer.id] { Image(uiImage: image).resizable().scaledToFill().frame(width: 58, height: 58).clipped() }
                                else { ProgressView().frame(width: 58, height: 58) }
                                Text("\(index+1)").font(.caption2.bold()).foregroundStyle(.white).padding(4).background(.black.opacity(0.65), in: Circle()).padding(3)
                            }.clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(model.selection == layer.id ? theme.accent : .clear, lineWidth: 2))
                        }.buttonStyle(.plain).accessibilityLabel(c("照片 \(index+1)", "Photo \(index+1)"))
                            .accessibilityIdentifier("grid.photo.\(index)")
                    }
                    Button { addPhotos(false) } label: { Image(systemName: "plus").frame(width: 58, height: 58).background(theme.surface, in: RoundedRectangle(cornerRadius: 8)) }
                        .disabled(photos.count >= 9).accessibilityLabel(c("添加照片", "Add photos")).accessibilityIdentifier("grid.photos.add")
                }.padding(2)
            }
        }.padding(.top, 4)
    }
    private func photoAction(_ icon: String, _ label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) { Image(systemName: icon); Text(label).font(.caption) }.frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("grid.action."+id)
    }
    private func select(_ id: UUID) {
        if let source = exchange {
            if model.swapPhotos(source, id) { exchange = nil }
            else if source == id { exchange = nil }
        } else { model.selection = id; tool = .photos }
    }
    private func openCrop(_ id: UUID) {
        guard let placement = model.geometry.placements.first(where: { $0.id == id && $0.layer.isPhoto && !$0.layer.locked }), model.gridImages[id] != nil else { return }
        exchange = nil; model.selection = id
        crop = CollageGridCrop(layer: placement.layer, aspect: placement.rect.width/placement.rect.height)
    }
}

private enum GridTool: String, CaseIterable, Identifiable {
    case templates, ratio, style, photos
    var id: String { rawValue }
    var icon: String { switch self { case .templates: return "rectangle.3.group"; case .ratio: return "aspectratio"; case .style: return "slider.horizontal.3"; case .photos: return "photo.on.rectangle" } }
    func title(_ language: AppLanguage) -> String {
        let index = Self.allCases.firstIndex(of: self)!
        return (language == .english ? ["Templates", "Ratio", "Style", "Photos"] : ["模板", "比例", "样式", "照片"])[index]
    }
}

/// Uses the export drawing code and cached downsampled sources, without a full-canvas bitmap per gesture.
private struct GridRenderedLayer: UIViewRepresentable {
    let layer: CollageLayer
    let image: UIImage?
    let document: CollageDocument
    func makeUIView(context: Context) -> LayerView { let view = LayerView(); view.isUserInteractionEnabled = false; view.isOpaque = false; view.backgroundColor = .clear; view.contentMode = .redraw; return view }
    func updateUIView(_ view: LayerView, context: Context) { view.layerValue = layer; view.image = image; view.document = document; view.setNeedsDisplay() }
    final class LayerView: UIView {
        var layerValue: CollageLayer?
        var image: UIImage?
        var document: CollageDocument?
        override func draw(_ rect: CGRect) {
            guard var layerValue, let document, let context = UIGraphicsGetCurrentContext() else { return }
            layerValue.rotation = 0
            // Text size is expressed in canvas units, not cell units.
            CollageRenderer.drawLayer(layerValue, rect: bounds, document: document, context: context, image: image)
        }
    }
}

private struct GridMiniature: View {
    let document: CollageDocument
    let images: [UUID: UIImage]
    var body: some View {
        GeometryReader { viewport in
            let geometry = CollageGeometry.make(document)
            let scale = min(viewport.size.width/geometry.size.width, viewport.size.height/geometry.size.height)
            ZStack(alignment: .topLeading) {
                Color(uiColor: CollageRenderer.color(document.background))
                ForEach(geometry.placements) { p in
                    GridRenderedLayer(layer: scaledText(p.layer, scale), image: images[p.id], document: document)
                        .frame(width: p.rect.width*scale, height: p.rect.height*scale)
                        .rotationEffect(.degrees(p.layer.rotation))
                        .position(x: p.rect.midX*scale, y: p.rect.midY*scale)
                }
            }.frame(width: geometry.size.width*scale, height: geometry.size.height*scale).clipped()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }.allowsHitTesting(false)
    }
}
private func scaledText(_ layer: CollageLayer, _ scale: CGFloat) -> CollageLayer {
    var result = layer; if !layer.isPhoto { result.fontSize *= scale }; return result
}

private struct GridDrag {
    let id: UUID
    var translation: CGSize
    var target: UUID?
}

private struct CollageGridCanvas: View {
    @ObservedObject var model: CollageEditorModel
    @EnvironmentObject private var store: DreamStore
    @Environment(\.albumTheme) private var theme
    let exchange: UUID?
    let select: (UUID) -> Void
    let crop: (UUID) -> Void
    @State private var drag: GridDrag?
    var body: some View {
        GeometryReader { viewport in
            let geometry = model.geometry
            let scale = min(max(1, viewport.size.width-32)/geometry.size.width, max(1, viewport.size.height-24)/geometry.size.height)
            let size = CGSize(width: geometry.size.width*scale, height: geometry.size.height*scale)
            ZStack(alignment: .topLeading) {
                Color(uiColor: CollageRenderer.color(model.document.background)).onTapGesture { if exchange == nil { model.selection = nil } }
                ForEach(geometry.placements) { p in
                    let rect = CGRect(x: p.rect.minX*scale, y: p.rect.minY*scale, width: p.rect.width*scale, height: p.rect.height*scale)
                    GridRenderedLayer(layer: scaledText(p.layer, scale), image: model.gridImages[p.id], document: model.document)
                        .opacity(drag?.id == p.id ? 0.25 : 1)
                        .overlay {
                            if p.layer.isPhoto {
                                GridTouchSurface(locked: p.layer.locked, tap: { select(p.id) }, doubleTap: { crop(p.id) }) { state, point, translation in
                                    let drop = CGPoint(x: (rect.minX+point.x)/scale, y: (rect.minY+point.y)/scale)
                                    let target = geometry.placements.first { $0.id != p.id && $0.layer.isPhoto && !$0.layer.locked && $0.rect.contains(drop) }?.id
                                    if state == .began || state == .changed { model.selection = p.id; drag = GridDrag(id: p.id, translation: translation, target: target) }
                                    else { if state == .ended, let target { _ = model.swapPhotos(p.id, target) }; drag = nil }
                                }
                            } else {
                                CollageLayerInput(model: model, layer: p.layer, canvasSize: size)
                            }
                        }
                        .overlay {
                            if model.selection == p.id || drag?.target == p.id {
                                Rectangle().stroke(theme.accent, style: StrokeStyle(lineWidth: drag?.target == p.id ? 4 : 2, dash: p.layer.locked ? [4] : [])).allowsHitTesting(false)
                            }
                        }
                        .overlay(alignment: .topTrailing) {
                            if model.selection == p.id { Image(systemName: p.layer.locked ? "lock.circle.fill" : "checkmark.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.white, theme.accent).padding(4).allowsHitTesting(false) }
                        }
                        .frame(width: rect.width, height: rect.height).rotationEffect(.degrees(p.layer.rotation))
                        .position(x: rect.midX, y: rect.midY)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(p.layer.isPhoto ? AlbumCopy.pick(store.appLanguage, "照片 \((model.document.layers.filter(\.isPhoto).firstIndex { $0.id == p.id } ?? 0)+1)", "Photo \((model.document.layers.filter(\.isPhoto).firstIndex { $0.id == p.id } ?? 0)+1)") : p.layer.text)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityValue(model.selection == p.id ? "selected" : "")
                        .accessibilityAction { select(p.id) }
                        .accessibilityAction(named: Text(AlbumCopy.pick(store.appLanguage, "裁切", "Crop"))) { crop(p.id) }
                        .accessibilityIdentifier("collage.layer."+p.id.uuidString)
                }
                if let drag, let p = geometry.placements.first(where: { $0.id == drag.id }) {
                    GridRenderedLayer(layer: p.layer, image: model.gridImages[p.id], document: model.document)
                        .frame(width: p.rect.width*scale, height: p.rect.height*scale).scaleEffect(1.04)
                        .shadow(color: .black.opacity(0.22), radius: 12, y: 6)
                        .position(x: p.rect.midX*scale+drag.translation.width, y: p.rect.midY*scale+drag.translation.height)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
                if model.gridImages.isEmpty { ProgressView().frame(width: size.width, height: size.height) }
            }.frame(width: size.width, height: size.height).clipped()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("collage.canvas")
        }.onDisappear { drag = nil }
    }
}

private struct GridTouchSurface: UIViewRepresentable {
    let locked: Bool
    let tap: () -> Void
    let doubleTap: () -> Void
    let drag: (UIGestureRecognizer.State, CGPoint, CGSize) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UIView {
        let view = UIView(); view.backgroundColor = .clear
        let c = context.coordinator
        let tap = UITapGestureRecognizer(target: c, action: #selector(Coordinator.tap))
        let double = UITapGestureRecognizer(target: c, action: #selector(Coordinator.doubleTap)); double.numberOfTapsRequired = 2
        tap.require(toFail: double)
        view.addGestureRecognizer(tap); view.addGestureRecognizer(double); view.addGestureRecognizer(c.press)
        return view
    }
    func updateUIView(_ view: UIView, context: Context) { context.coordinator.input = self; context.coordinator.press.isEnabled = !locked }
    final class Coordinator: NSObject {
        var input: GridTouchSurface
        var start = CGPoint.zero
        lazy var press: UILongPressGestureRecognizer = { let p = UILongPressGestureRecognizer(target: self, action: #selector(move(_:))); p.minimumPressDuration = 0.3; return p }()
        init(_ input: GridTouchSurface) { self.input = input }
        @objc func tap() { input.tap() }
        @objc func doubleTap() { if !input.locked { input.doubleTap() } }
        @objc func move(_ recognizer: UILongPressGestureRecognizer) {
            let point = recognizer.location(in: recognizer.view)
            if recognizer.state == .began { start = point; UISelectionFeedbackGenerator().selectionChanged() }
            input.drag(recognizer.state, point, CGSize(width: point.x-start.x, height: point.y-start.y))
        }
    }
}

private struct CollageGridCropView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: DreamStore
    @Environment(\.albumTheme) private var theme
    @State var crop: CollageGridCrop
    let image: UIImage?
    let document: CollageDocument
    let commit: (CollageGridCrop) -> Void
    private func c(_ zh: String, _ en: String) -> String { AlbumCopy.pick(store.appLanguage, zh, en) }
    var body: some View {
        VStack(spacing: 20) {
            GeometryReader { viewport in
                let width = min(viewport.size.width-32, (viewport.size.height-32)*crop.aspect)
                let size = CGSize(width: max(1, width), height: max(1, width/crop.aspect))
                GridRenderedLayer(layer: crop.layer, image: image, document: document)
                    .background(Color(uiColor: CollageRenderer.color(document.background)))
                    .overlay { GridCropSurface(crop: $crop, size: size) }
                    .overlay(Rectangle().stroke(theme.accent.opacity(0.6), lineWidth: 1).allowsHitTesting(false))
                    .frame(width: size.width, height: size.height).clipped()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(c("裁切画布", "Crop canvas"))
                    .accessibilityValue(String(format: "%.2f", crop.layer.zoom))
                    .accessibilityIdentifier("grid.crop.canvas")
            }
            Picker(c("显示方式", "Photo fit"), selection: Binding(get: { crop.layer.photoFit ?? .fill }, set: { value in crop.reset(); crop.layer.photoFit = value })) {
                Text(c("填满", "Fill")).tag(CollagePhotoFit.fill)
                Text(c("完整显示", "Fit")).tag(CollagePhotoFit.fit)
            }.pickerStyle(.segmented).padding(.horizontal, 24).accessibilityIdentifier("grid.crop.fit")
            HStack {
                Image(systemName: "minus.magnifyingglass").accessibilityHidden(true)
                Slider(value: $crop.layer.zoom, in: 1...5).accessibilityLabel(c("缩放", "Zoom")).accessibilityIdentifier("grid.crop.zoom")
                Image(systemName: "plus.magnifyingglass").accessibilityHidden(true)
            }.padding(.horizontal, 24).disabled(crop.layer.photoFit == .fit)
            Button(c("重置", "Reset")) { crop.reset() }.frame(minHeight: 44).accessibilityIdentifier("grid.crop.reset")
        }.padding(.bottom, 16).background(AlbumBackground())
            .navigationTitle(c("裁切", "Crop")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(c("取消", "Cancel")) { dismiss() }.accessibilityIdentifier("grid.crop.cancel") }
                ToolbarItem(placement: .confirmationAction) { Button(c("完成", "Done")) { commit(crop); dismiss() }.accessibilityIdentifier("grid.crop.done") }
            }
    }
}

private struct GridCropSurface: UIViewRepresentable {
    @Binding var crop: CollageGridCrop
    let size: CGSize
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UIView {
        let view = UIView(); view.backgroundColor = .clear; view.isMultipleTouchEnabled = true
        for recognizer in [context.coordinator.pan, context.coordinator.pinch] as [UIGestureRecognizer] { recognizer.delegate = context.coordinator; view.addGestureRecognizer(recognizer) }
        return view
    }
    func updateUIView(_ view: UIView, context: Context) { context.coordinator.input = self }
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var input: GridCropSurface
        var base: CollageLayer?
        var active = Set<ObjectIdentifier>()
        lazy var pan = UIPanGestureRecognizer(target: self, action: #selector(change(_:)))
        lazy var pinch = UIPinchGestureRecognizer(target: self, action: #selector(change(_:)))
        init(_ input: GridCropSurface) { self.input = input }
        func gestureRecognizer(_ a: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith b: UIGestureRecognizer) -> Bool { a.view === b.view }
        @objc func change(_ recognizer: UIGestureRecognizer) {
            if recognizer.state == .began {
                if active.isEmpty { base = input.crop.layer; pan.setTranslation(.zero, in: pan.view); pinch.scale = 1 }
                active.insert(ObjectIdentifier(recognizer))
            }
            guard let base else { return }
            let translation = pan.translation(in: pan.view)
            input.crop.transform(from: base, translation: CGSize(width: translation.x, height: translation.y), scale: pinch.scale, box: input.size)
            if [.ended, .cancelled, .failed].contains(recognizer.state) {
                active.remove(ObjectIdentifier(recognizer)); if active.isEmpty { self.base = nil }
            }
        }
    }
}
