import SwiftUI

/// App appearance is a device preference, independent of dream data and backups.
enum AppTheme: String, CaseIterable, Identifiable {
    case silver, mistBlue, iceMint, bluePearl
    static let storageKey = "dream_album.appearance_theme.v1"
    var id: String { rawValue }
    static func resolve(_ value: String) -> AppTheme { AppTheme(rawValue: value) ?? .silver }

    /// Apply the selected redesign once, then respect subsequent theme choices.
    static func installSilverAppearance(in defaults: UserDefaults = .standard) {
        let key = "dream_album.silver_appearance.v1"
        guard !defaults.bool(forKey: key) else { return }
        defaults.set(AppTheme.silver.rawValue, forKey: storageKey)
        defaults.set(true, forKey: key)
    }
    var utilityBackground: Color { self == .silver ? Color(hex: 0xFAFAFC) : background }
    var separator: Color { self == .silver ? Color(hex: 0xDDDEE3) : secondary.opacity(0.18) }

    func title(_ language: AppLanguage) -> String {
        switch self {
        case .silver: return AlbumCopy.pick(language, "原生银灰", "Native Silver")
        case .mistBlue: return AlbumCopy.pick(language, "雾蓝晨光", "Morning Blue")
        case .iceMint: return AlbumCopy.pick(language, "冰蓝薄荷", "Ice Mint")
        case .bluePearl: return AlbumCopy.pick(language, "蓝紫珍珠", "Blue Pearl")
        }
    }
    var background: Color {
        switch self {
        case .silver: return Color(hex: 0xF2F2F5)
        case .mistBlue: return Color(hex: 0xCEE2F7)
        case .iceMint: return Color(hex: 0xCCEDE5)
        case .bluePearl: return Color(hex: 0xD7D4F4)
        }
    }
    var gradient: LinearGradient {
        let colors: [Color]
        switch self {
        case .silver: colors = [Color(hex: 0xF2F2F5), Color(hex: 0xF2F2F5)]
        case .mistBlue: colors = [Color(hex: 0xC4DDF6), Color(hex: 0xD8E9FA), Color(hex: 0xC7DEF4)]
        case .iceMint: colors = [Color(hex: 0xC3E7F6), Color(hex: 0xD3EFEA), Color(hex: 0xBFE7D9)]
        case .bluePearl: colors = [Color(hex: 0xCAD9F6), Color(hex: 0xDDDCF6), Color(hex: 0xD5C5EF)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    var surface: Color { self == .silver ? .white : .white.opacity(0.80) }
    var primary: Color {
        switch self {
        case .silver: return Color(hex: 0x202124)
        case .mistBlue: return Color(hex: 0x233A58)
        case .iceMint: return Color(hex: 0x203E49)
        case .bluePearl: return Color(hex: 0x30334D)
        }
    }
    var secondary: Color {
        switch self {
        case .silver: return Color(hex: 0x66686E)
        case .mistBlue: return Color(hex: 0x4C5E76)
        case .iceMint: return Color(hex: 0x466269)
        case .bluePearl: return Color(hex: 0x53536A)
        }
    }
    var accent: Color {
        switch self {
        case .silver: return Color(hex: 0x2F6398)
        case .mistBlue: return Color(hex: 0x205B9F)
        case .iceMint: return Color(hex: 0x066A7C)
        case .bluePearl: return Color(hex: 0x45499B)
        }
    }
    var destructive: Color { Color(hex: 0xC13F43) }
}

private extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 255) / 255,
                  green: Double((hex >> 8) & 255) / 255,
                  blue: Double(hex & 255) / 255)
    }
}

private struct AppThemeKey: EnvironmentKey { static let defaultValue = AppTheme.silver }
extension EnvironmentValues {
    var albumTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}

struct AppThemePicker: View {
    @EnvironmentObject private var store: DreamStore
    @AppStorage(AppTheme.storageKey) private var themeID = AppTheme.silver.rawValue
    @Environment(\.albumTheme) private var theme
    private func c(_ zh: String, _ en: String) -> String { AlbumCopy.pick(store.appLanguage, zh, en) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(AppTheme.allCases) { option in
                    Button { themeID = option.rawValue } label: {
                        VStack(spacing: 0) {
                            option.gradient.frame(height: 72)
                                .overlay(alignment: .bottomLeading) {
                                    Image(systemName: "photo.on.rectangle")
                                        .font(.title2).foregroundStyle(option.accent).padding(16)
                                }
                            HStack {
                                Text(option.title(store.appLanguage)).font(.headline).foregroundStyle(theme.primary)
                                Spacer()
                                Image(systemName: selected(option) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected(option) ? theme.accent : theme.secondary.opacity(0.6))
                            }.padding(16).background(theme.surface)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay { RoundedRectangle(cornerRadius: 14).stroke(selected(option) ? theme.accent : .clear, lineWidth: 2) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(option.title(store.appLanguage))
                    .accessibilityValue(selected(option) ? c("已选择", "Selected") : c("未选择", "Not selected"))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAddTraits(selected(option) ? .isSelected : [])
                    .accessibilityIdentifier("theme.option." + option.rawValue)
                }
            }.frame(maxWidth: 600).padding(24).frame(maxWidth: .infinity)
        }
        .background(AlbumBackground())
        .navigationTitle(c("背景主题", "Background theme"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(theme.background, for: .navigationBar)
    }
    private func selected(_ option: AppTheme) -> Bool { AppTheme.resolve(themeID) == option }
}
