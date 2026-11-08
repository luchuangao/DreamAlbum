import SwiftUI

struct CollageEditor: View {
    @EnvironmentObject private var store: DreamStore
    @Environment(\.albumTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @StateObject private var model: CollageEditorModel
    var onClose: (() -> Void)?
    @State private var tools = false
    @State private var tool = "layout"
    @State private var layers = false
    @State private var exporting = false
    @State private var photos = false
    @State private var replacing = false
    @State private var changingKind: CollageKind?
    init(document: CollageDocument, workspace: CollageStore, onClose: (() -> Void)? = nil) {
        _model = StateObject(wrappedValue: CollageEditorModel(document: document, store: workspace)); self.onClose = onClose
    }
    private func c(_ zh: String, _ en: String) -> String { AlbumCopy.pick(store.appLanguage, zh, en) }
    var body: some View {
        GeometryReader { outer in
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    if model.pages.count > 1 {
                        Picker(c("分页", "Page"), selection: $model.page) { ForEach(model.pages.indices, id: \.self) { Text("\($0+1) / \(model.pages.count)").tag($0) } }.padding(.horizontal)
                    }
                    CollageCanvas(model: model)
                    toolBar
                }
                if outer.size.width >= 750 { inspector.frame(width: 300).background(theme.surface) }
            }
        }
        .background(AlbumBackground()).navigationTitle(model.document.name).navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true).toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(c("完成", "Done")) { model.endGesture(); if model.error == nil { if let onClose { onClose() } else { dismiss() } } }.accessibilityIdentifier("collage.editor.done") }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }.disabled(model.undoItems.isEmpty).keyboardShortcut("z", modifiers: .command).accessibilityLabel(c("撤销", "Undo")).accessibilityIdentifier("collage.undo")
                Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }.disabled(model.redoItems.isEmpty).keyboardShortcut("z", modifiers: [.command, .shift]).accessibilityLabel(c("重做", "Redo")).accessibilityIdentifier("collage.redo")
                Button(c("导出", "Export")) { model.endGesture(); exporting = true }.disabled(!model.document.isValidCount || model.preview == nil).accessibilityIdentifier("collage.export")
            }
        }
        .sheet(isPresented: $tools) { NavigationStack { inspector.navigationTitle(c("编辑拼图", "Edit collage")).toolbar { ToolbarItem(placement: .confirmationAction) { Button(c("完成", "Done")) { model.endGesture(); tools = false } } } }.presentationDetents([.medium, .large]) }
        .sheet(isPresented: $layers) { NavigationStack { CollageLayersView(model: model) } }
        .sheet(isPresented: $photos) { NavigationStack { CollageAddPhotosView(model: model, replacing: replacing) } }
        .sheet(item: $changingKind) { kind in NavigationStack { CollageAdjustKindView(model: model, kind: kind) } }
        .sheet(isPresented: $exporting) { NavigationStack { CollageExportView(model: model) } }
        .onAppear { model.flush() }
        .onChange(of: model.page) { _, _ in model.schedulePreview() }
        .onChange(of: phase) { _, value in if value != .active { model.endGesture() } }
        .onDisappear { if !tools && !layers && !photos && changingKind == nil && !exporting { model.close() } }
        .alert(c("无法保存拼图", "Could not save collage"), isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button(c("重试", "Retry")) { model.flush() }
            Button(c("好", "OK"), role: .cancel) { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
    private var inspector: some View {
        CollageInspector(model: model, tab: tool, changeKind: { kind in
            if kind.limits.contains(model.document.photoCount) {
                model.apply { doc in doc.setKind(kind); if kind == .freeform && !doc.hasFreeLayout { doc.arrangeFreeLayers() } }
            } else { tools = false; changingKind = kind }
        })
    }
    private var toolBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 22) {
                if let selected = model.selected {
                    if selected.isPhoto {
                        action("arrow.triangle.2.circlepath", c("替换", "Replace")) { replacing = true; photos = true }
                            .disabled(selected.locked)
                        action("crop", c("裁切", "Crop")) { tool = "crop"; tools = true }
                        action("square", c("边框", "Border")) { tool = "border"; tools = true }
                    } else { action("textformat", c("文字", "Text")) { tool = "text"; tools = true } }
                    action("square.3.layers.3d", c("图层", "Layers")) { layers = true }
                    action("trash", c("移除", "Remove")) { model.apply { $0.layers.removeAll { $0.id == selected.id } }; model.selection = nil }
                        .disabled(selected.locked || (selected.isPhoto && model.document.photoCount <= model.document.kind.limits.lowerBound))
                } else {
                    action("rectangle.3.group", c("布局", "Layout")) { tool = "layout"; tools = true }
                    action("aspectratio", c("比例", "Ratio")) { tool = "ratio"; tools = true }
                    action("paintpalette", c("背景", "Background")) { tool = "background"; tools = true }
                    Menu {
                        Button(c("照片", "Photos"), systemImage: "photo") { replacing = false; photos = true }.disabled(model.document.photoCount >= model.document.kind.limits.upperBound)
                        Button(c("文字", "Text"), systemImage: "textformat") {
                            let item = CollageLayer(text: c("写点什么", "Your text"), x: 0.1, y: 0.4, width: 0.8, height: 0.2)
                            model.apply { $0.layers.append(item) }; model.selection = item.id; tool = "text"; tools = true
                        }.disabled(model.document.kind == .strip || model.document.layers.filter { !$0.isPhoto }.count >= 10)
                    } label: { iconLabel("plus", c("添加", "Add")) }.accessibilityIdentifier("collage.add")
                    action("square.3.layers.3d", c("图层", "Layers")) { layers = true }
                }
            }.padding(.horizontal, 20).padding(.vertical, 8)
        }.background(theme.utilityBackground)
    }
    private func iconLabel(_ icon: String, _ text: String) -> some View {
        VStack(spacing: 4) { Image(systemName: icon).font(.title3); Text(text).font(.caption) }.frame(minWidth: 44, minHeight: 48)
    }
    private func action(_ icon: String, _ text: String, _ perform: @escaping () -> Void) -> some View {
        Button(action: perform) { iconLabel(icon, text) }.buttonStyle(.plain).foregroundStyle(theme.accent)
    }
}

struct CollageCanvas: View {
    @ObservedObject var model: CollageEditorModel
    @Environment(\.albumTheme) private var theme
    var body: some View {
        GeometryReader { viewport in
            let page = model.pages.indices.contains(model.page) ? model.pages[model.page] : CGRect(x: 0, y: 0, width: 1, height: 1)
            let ratio = page.width / max(1, page.height)
            let width = model.document.kind == .strip && model.document.horizontal ? max(viewport.size.width-24, min(600, viewport.size.height-24)*ratio) : min(viewport.size.width-24, model.document.kind == .strip ? 700 : max(1, viewport.size.height-24)*ratio)
            let height = width / max(0.001, ratio)
            let scale = width / max(1, page.width)
            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    Color(uiColor: CollageRenderer.color(model.document.background)).onTapGesture { model.selection = nil }
                    if let image = model.preview { Image(uiImage: image).resizable().frame(width: width, height: height).allowsHitTesting(false) }
                    else { ProgressView().frame(width: width, height: min(height, 400)) }
                    ForEach(model.geometry.placements.filter { $0.rect.intersects(page) }) { placement in
                        let rect = placement.rect.offsetBy(dx: -page.minX, dy: -page.minY)
                        CollageLayerInput(model: model, layer: placement.layer,
                                          canvasSize: CGSize(width: model.geometry.size.width * scale, height: model.geometry.size.height * scale))
                            .overlay {
                                if model.selection == placement.id {
                                    Rectangle().stroke(theme.accent, style: StrokeStyle(lineWidth: 2, dash: placement.layer.locked ? [4] : []))
                                        .allowsHitTesting(false)
                                }
                            }
                            .frame(width: max(1, rect.width*scale), height: max(1, rect.height*scale))
                            .rotationEffect(.degrees(placement.layer.rotation))
                            .position(x: rect.midX*scale, y: rect.midY*scale)
                    }
                    if model.document.kind == .freeform, let selected = model.selected {
                        if abs(selected.x+selected.width/2-0.5) < 0.002 { Rectangle().fill(theme.accent).frame(width: 1, height: height).position(x: width/2, y: height/2).allowsHitTesting(false) }
                        if abs(selected.y+selected.height/2-0.5) < 0.002 { Rectangle().fill(theme.accent).frame(width: width, height: 1).position(x: width/2, y: height/2).allowsHitTesting(false) }
                    }
                }.frame(width: max(1, width), height: max(1, height)).clipped().padding(12)
            }.scrollDisabled(model.document.kind != .strip)
                .frame(maxWidth: .infinity, maxHeight: .infinity).accessibilityIdentifier("collage.canvas")
        }
    }
}

/// The touch surface has exactly the layer's bounds. Its window coordinate space
/// stays stable while SwiftUI moves and rotates the underlying layer.
private struct CollageLayerInput: UIViewRepresentable {
    let model: CollageEditorModel
    let layer: CollageLayer
    let canvasSize: CGSize

    func makeCoordinator() -> Coordinator { Coordinator(input: self) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true
        view.isAccessibilityElement = true
        let coordinator = context.coordinator
        let tap = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.select))
        view.addGestureRecognizer(tap)
        for recognizer in [coordinator.pan, coordinator.pinch, coordinator.rotate] as [UIGestureRecognizer] {
            recognizer.delegate = coordinator
            view.addGestureRecognizer(recognizer)
        }
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        let coordinator = context.coordinator
        coordinator.input = self
        view.accessibilityIdentifier = "collage.layer." + layer.id.uuidString
        view.accessibilityLabel = layer.isPhoto ? model.document.name : layer.text
        coordinator.pan.minimumNumberOfTouches = model.document.kind == .strip ? 2 : 1
        coordinator.pan.isEnabled = !layer.locked
        coordinator.pinch.isEnabled = !layer.locked
        coordinator.rotate.isEnabled = !layer.locked && (model.document.kind == .freeform || !layer.isPhoto)
    }

    @MainActor final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var input: CollageLayerInput
        private var active = Set<ObjectIdentifier>()
        private var translation = CGSize.zero
        private var magnification = 1.0
        private var degrees = 0.0
        lazy var pan = UIPanGestureRecognizer(target: self, action: #selector(transform(_:)))
        lazy var pinch = UIPinchGestureRecognizer(target: self, action: #selector(transform(_:)))
        lazy var rotate = UIRotationGestureRecognizer(target: self, action: #selector(transform(_:)))

        init(input: CollageLayerInput) { self.input = input }
        @objc func select() { input.model.selection = input.layer.id }

        func gestureRecognizer(_ first: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith second: UIGestureRecognizer) -> Bool {
            first.view === second.view
        }

        @objc func transform(_ recognizer: UIGestureRecognizer) {
            let model = input.model
            let token = ObjectIdentifier(recognizer)
            if recognizer.state == .began {
                if active.isEmpty {
                    translation = .zero
                    magnification = 1
                    degrees = 0
                    model.beginGesture()
                }
                active.insert(token)
            }
            guard active.contains(token) else { return }
            if recognizer === pan {
                let point = pan.translation(in: pan.view?.window)
                translation = CGSize(width: point.x, height: point.y)
            } else if recognizer === pinch { magnification = pinch.scale }
            else { degrees = rotate.rotation * 180 / .pi }
            model.gesture(id: input.layer.id, translation: translation, zoom: magnification,
                          angle: degrees, canvasSize: input.canvasSize)
            switch recognizer.state {
            case .ended, .cancelled, .failed:
                active.remove(token)
                if active.isEmpty {
                    if recognizer.state == .ended, model.document.kind == .grid, magnification == 1 {
                        model.finishGridDrag(source: input.layer.id, translation: translation, canvas: input.canvasSize)
                    } else { model.endGesture() }
                }
            default: break
            }
        }
    }
}

struct CollageInspector: View {
    @ObservedObject var model: CollageEditorModel
    @EnvironmentObject private var store: DreamStore
    @Environment(\.albumTheme) private var theme
    let tab: String
    let changeKind: (CollageKind) -> Void
    private func c(_ zh: String, _ en: String) -> String { AlbumCopy.pick(store.appLanguage, zh, en) }
    var body: some View {
        Form {
            if let selected = model.selected {
                Section(selected.isPhoto ? c("照片", "Photo") : c("文字", "Text")) {
                    Toggle(c("锁定", "Lock"), isOn: layerBinding(\.locked, fallback: false))
                    if !selected.isPhoto {
                        TextField(c("文字", "Text"), text: limitedLayerText(\.text, count: 280), axis: .vertical).lineLimit(2...6)
                        layerSlider(c("字号", "Font size"), \.fontSize, 0.015...0.15)
                        ColorPicker(c("文字颜色", "Text color"), selection: layerColor)
                    } else {
                        layerSlider(c("边框", "Border"), \.border, 0...0.12)
                        layerSlider(c("缩放", "Zoom"), \.zoom, 1...5)
                        layerSlider(c("水平位置", "Horizontal position"), \.offsetX, -1...1)
                        layerSlider(c("垂直位置", "Vertical position"), \.offsetY, -1...1)
                        if model.document.kind == .strip {
                            layerSlider(c("裁去顶部", "Crop top"), \.cropTop, 0...0.45)
                            layerSlider(c("裁去底部", "Crop bottom"), \.cropBottom, 0...0.45)
                            layerSlider(c("裁去左侧", "Crop left"), \.cropLeft, 0...0.45)
                            layerSlider(c("裁去右侧", "Crop right"), \.cropRight, 0...0.45)
                        }
                        if model.document.kind == .comparison { TextField(c("标签", "Label"), text: limitedLayerText(\.label, count: 40)) }
                    }
                    if model.document.kind == .freeform || !selected.isPhoto {
                        layerSlider(c("旋转", "Rotation"), \.rotation, -180...180)
                        layerSlider(c("宽度", "Width"), \.width, 0.03...1.5)
                        layerSlider(c("高度", "Height"), \.height, 0.03...1.5)
                    }
                }.disabled(selected.locked)
                if selected.locked { Button(c("解锁", "Unlock")) { model.editLayer { $0.locked = false } } }
            }
            Section(c("排版", "Layout")) {
                TextField(c("拼图名称", "Collage name"), text: docBinding(\.name)).accessibilityIdentifier("collage.name")
                Picker(c("类型", "Type"), selection: Binding(get: { model.document.kind }, set: changeKind)) {
                    ForEach(CollageKind.allCases) { Text($0.title(store.appLanguage)).tag($0) }
                }
                if model.document.kind == .strip { Toggle(c("横向拼接", "Horizontal"), isOn: Binding(get: { model.document.horizontal }, set: { value in model.apply { $0.horizontal = value } })) }
                else {
                    Picker(c("比例", "Ratio"), selection: Binding(get: { model.document.ratio }, set: { value in model.apply { $0.ratio = value } })) { ForEach(CollageRatio.allCases) { Text($0.rawValue).tag($0) } }
                    if model.document.kind != .freeform {
                        Picker(c("模板", "Template"), selection: Binding(get: { model.document.layout }, set: { value in model.apply { $0.layout = value } })) {
                            ForEach(0..<3, id: \.self) { i in Text(templateName(i)).tag(i) }
                        }.pickerStyle(.menu)
                    }
                }
                ColorPicker(c("背景", "Background"), selection: backgroundColor, supportsOpacity: false)
                docSlider(c("图片间距", "Spacing"), \.spacing, 0...0.06)
                docSlider(c("外边距", "Margin"), \.margin, 0...0.12)
                docSlider(c("圆角", "Corners"), \.corner, 0...0.2)
            }
            if model.document.kind == .poster {
                Section(c("海报文字", "Poster text")) {
                    TextField(c("标题", "Title"), text: docBinding(\.title))
                    TextField(c("日期", "Date"), text: docBinding(\.dateText))
                    TextField(c("简短文字", "Short message"), text: docBinding(\.subtitle), axis: .vertical).lineLimit(2...4)
                }
            }
            if model.document.kind == .comparison {
                Section(c("日期", "Date")) { TextField(c("日期（可选）", "Date (optional)"), text: docBinding(\.dateText)) }
            }
        }.scrollContentBackground(.hidden).background(AlbumBackground())
    }
    private func templateName(_ i: Int) -> String {
        switch model.document.kind {
        case .poster: return [c("目标", "Goal"), c("旅行", "Travel"), c("成长", "Growth")][i]
        case .comparison: return [c("左右", "Side by side"), c("上下", "Vertical"), c("四格", "Four panels")][i]
        default: return [c("等分", "Equal"), c("一大多小", "Hero left"), c("上下组合", "Hero above")][i]
        }
    }
    private func docBinding(_ key: WritableKeyPath<CollageDocument, String>) -> Binding<String> {
        Binding(get: { model.document[keyPath: key] }, set: { text in model.apply { $0[keyPath: key] = String(text.prefix(key == \.subtitle ? 120 : 40)) } })
    }
    private func layerBinding<T>(_ key: WritableKeyPath<CollageLayer, T>, fallback: T) -> Binding<T> {
        Binding(get: { model.selected?[keyPath: key] ?? fallback }, set: { value in model.editLayer { $0[keyPath: key] = value } })
    }
    private func limitedLayerText(_ key: WritableKeyPath<CollageLayer, String>, count: Int) -> Binding<String> {
        Binding(get: { model.selected?[keyPath: key] ?? "" }, set: { value in model.editLayer { $0[keyPath: key] = String(value.prefix(count)) } })
    }
    private func docSlider(_ title: String, _ key: WritableKeyPath<CollageDocument, Double>, _ range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading) { Text(title).font(.caption); Slider(value: Binding(get: { model.document[keyPath: key] }, set: { value in model.beginGesture(); model.document[keyPath: key] = value; model.schedulePreview() }), in: range, onEditingChanged: { if !$0 { model.endGesture() } }) }
    }
    private func layerSlider(_ title: String, _ key: WritableKeyPath<CollageLayer, Double>, _ range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading) { Text(title).font(.caption); Slider(value: Binding(get: { model.selected?[keyPath: key] ?? range.lowerBound }, set: { value in
            guard let id = model.selection, let i = model.document.layers.firstIndex(where: { $0.id == id }) else { return }
            model.beginGesture(); model.document.layers[i][keyPath: key] = value; model.schedulePreview()
        }), in: range, onEditingChanged: { if !$0 { model.endGesture() } }) }
    }
    private var backgroundColor: Binding<Color> { Binding(get: { Color(uiColor: CollageRenderer.color(model.document.background)) }, set: { value in model.apply { $0.background = hex(value) } }) }
    private var layerColor: Binding<Color> { Binding(get: { Color(uiColor: CollageRenderer.color(model.selected?.textColor ?? "202124")) }, set: { value in model.editLayer { $0.textColor = hex(value) } }) }
    private func hex(_ color: Color) -> String { var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0; UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a); return String(format: "%02X%02X%02X", Int(r*255), Int(g*255), Int(b*255)) }
}

struct CollageLayersView: View {
    @ObservedObject var model: CollageEditorModel
    @EnvironmentObject private var store: DreamStore
    @Environment(\.dismiss) private var dismiss
    private func c(_ zh: String, _ en: String) -> String { AlbumCopy.pick(store.appLanguage, zh, en) }
    var body: some View {
        List {
            ForEach(Array(model.document.layers.enumerated()), id: \.element.id) { index, layer in
                HStack {
                    Button { model.selection = layer.id; dismiss() } label: { Label(layer.isPhoto ? c("照片 \(index+1)", "Photo \(index+1)") : layer.text, systemImage: layer.isPhoto ? "photo" : "textformat").lineLimit(2) }
                    Spacer()
                    Button { model.apply { if let i = $0.layers.firstIndex(where: { $0.id == layer.id }) { $0.layers[i].locked.toggle() } } } label: { Image(systemName: layer.locked ? "lock.fill" : "lock.open") }.buttonStyle(.borderless).accessibilityLabel(c("锁定或解锁", "Lock or unlock"))
                }
            }.onMove { from, to in model.apply { $0.layers.move(fromOffsets: from, toOffset: to) } }
        }.environment(\.editMode, .constant(.active)).navigationTitle(c("图层与顺序", "Layers & order"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(c("完成", "Done")) { dismiss() } } }
    }
}
