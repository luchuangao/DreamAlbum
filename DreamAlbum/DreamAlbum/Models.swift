import Foundation

enum AppFeatureFlags {
    static let paidAccessEnabled = false
}

enum BackgroundImageChoice: String, Codable, CaseIterable, Identifiable {
    case morningClouds
    case beachVacation
    case oceanSurf
    case dreamNight
    case worldSea
    case worldLand
    case worldSky
    case worldGalaxy
    case custom

    static var availableBackgrounds: [BackgroundImageChoice] {
        [.worldSea, .worldLand, .worldSky, .worldGalaxy]
    }

    var isCurrentBuiltInBackground: Bool {
        Self.availableBackgrounds.contains(self)
    }

    var id: String { rawValue }

    var assetName: String? {
        switch self {
        case .morningClouds: return "MorningCloudsBackground"
        case .beachVacation: return "BeachVacationBackground"
        case .oceanSurf: return "OceanSurfBackground"
        case .dreamNight: return "DreamNightBackground"
        case .worldSea: return "WorldSeaBackground"
        case .worldLand: return "WorldLandBackground"
        case .worldSky: return "WorldSkyBackground"
        case .worldGalaxy: return "WorldGalaxyBackground"
        case .custom: return nil
        }
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .morningClouds: return language == .english ? "Morning Clouds" : "晨光云海"
        case .beachVacation: return language == .english ? "Beach Vacation" : "清透沙滩"
        case .oceanSurf: return language == .english ? "Ocean Surf" : "碧海冲浪"
        case .dreamNight: return language == .english ? "Dream Night" : "梦幻夜空"
        case .worldSea: return language == .english ? "Sea" : "海"
        case .worldLand: return language == .english ? "Land" : "陆"
        case .worldSky: return language == .english ? "Sky" : "空"
        case .worldGalaxy: return language == .english ? "Galaxy" : "银河"
        case .custom: return language == .english ? "My Background" : "我的背景"
        }
    }
}

enum BackgroundContrast: String, Codable {
    case light
    case regular
    case dark
}

enum AlbumBackgroundStyle: String, Codable, CaseIterable, Identifiable {
    case morningMistBlue
    case rainBlue
    case porcelainWhite
    case mistPink
    case lakeBlue

    static var allCases: [AlbumBackgroundStyle] {
        [.rainBlue, .porcelainWhite, .mistPink, .lakeBlue]
    }

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .morningMistBlue: return language == .english ? "Rain Blue" : "雨后蓝"
        case .rainBlue: return language == .english ? "Rain Blue" : "雨后蓝"
        case .porcelainWhite: return language == .english ? "Porcelain" : "瓷白蓝"
        case .mistPink: return language == .english ? "Mist Pink" : "雾粉色"
        case .lakeBlue: return language == .english ? "Lake Blue" : "湖光蓝"
        }
    }
}

enum SettingsDisplayStyle: String, Codable, CaseIterable, Identifiable {
    case collage
    case beach
    case porcelain
    case magazine
    case compact
    case dashboard

    var id: String { rawValue }

    static var allCases: [SettingsDisplayStyle] {
        [.magazine, .compact, .dashboard]
    }

    static var freeCases: [SettingsDisplayStyle] {
        [.magazine, .compact, .dashboard]
    }

    static var premiumCases: [SettingsDisplayStyle] {
        []
    }

    var requiresPremium: Bool {
        AppFeatureFlags.paidAccessEnabled && Self.premiumCases.contains(self)
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .collage: return language == .english ? "Collage" : "潮流拼贴"
        case .beach: return language == .english ? "Beach" : "沙滩风格"
        case .porcelain: return language == .english ? "Porcelain Blue" : "青花瓷"
        case .magazine: return language == .english ? "Cover Flow" : "封面流"
        case .compact: return language == .english ? "Four Grid" : "四宫格"
        case .dashboard: return language == .english ? "Timeline" : "时间轴"
        }
    }
}

enum TimelineDisplayStyle: String, Codable, CaseIterable, Identifiable {
    case timeline
    case card

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .timeline: return language == .english ? "Timeline" : "时间轴"
        case .card: return language == .english ? "Cards" : "卡片"
        }
    }
}

enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case chinese
    case english

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chinese: return "中文"
        case .english: return "English"
        }
    }
}

enum AlbumCopy {
    static func pick(_ language: AppLanguage, _ chinese: String, _ english: String) -> String {
        language == .english ? english : chinese
    }
}

enum DreamMood: String, Codable, CaseIterable, Identifiable {
    case positive
    case negative

    var id: String { rawValue }

    var title: String {
        switch self {
        case .positive: return "还不错"
        case .negative: return "不太好"
        }
    }

    var symbol: String {
        switch self {
        case .positive: return "sun.max.fill"
        case .negative: return "cloud.rain.fill"
        }
    }

    var score: Int {
        switch self {
        case .positive: return 1
        case .negative: return -1
        }
    }
}

struct DreamLog: Identifiable, Codable, Equatable {
    var id = UUID()
    var action: String
    var mood: DreamMood
    var date: Date
    var imagePaths: [String] = []
    var comments: [DreamComment] = []
}

struct DreamComment: Identifiable, Codable, Equatable {
    var id = UUID()
    var text: String
    var date: Date
}

struct DreamStage: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var targetDate: Date?
    var isDone: Bool = false
    var doneAt: Date?
    var createdAt = Date()

    init(id: UUID = UUID(), title: String, targetDate: Date? = nil, isDone: Bool = false, doneAt: Date? = nil, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.targetDate = targetDate
        self.isDone = isDone
        self.doneAt = doneAt
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case targetDate
        case date
        case isDone
        case doneAt
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decode(String.self, forKey: .title)
        targetDate = try container.decodeIfPresent(Date.self, forKey: .targetDate)
            ?? container.decodeIfPresent(Date.self, forKey: .date)
        isDone = try container.decodeIfPresent(Bool.self, forKey: .isDone) ?? false
        doneAt = try container.decodeIfPresent(Date.self, forKey: .doneAt)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(targetDate, forKey: .targetDate)
        try container.encode(isDone, forKey: .isDone)
        try container.encodeIfPresent(doneAt, forKey: .doneAt)
        try container.encode(createdAt, forKey: .createdAt)
    }
}

struct Dream: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var visionText: String = ""
    var imagePaths: [String]
    var logs: [DreamLog] = []
    var milestones: [DreamStage] = []
    var createdAt = Date()
    var isArchived = false
    var archivedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        visionText: String = "",
        imagePaths: [String],
        logs: [DreamLog] = [],
        milestones: [DreamStage] = [],
        createdAt: Date = Date(),
        isArchived: Bool = false,
        archivedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.visionText = visionText
        self.imagePaths = imagePaths
        self.logs = logs
        self.milestones = milestones
        self.createdAt = createdAt
        self.isArchived = isArchived
        self.archivedAt = archivedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case visionText
        case imagePaths
        case logs
        case milestones
        case createdAt
        case isArchived
        case archivedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decode(String.self, forKey: .title)
        visionText = try container.decodeIfPresent(String.self, forKey: .visionText) ?? ""
        imagePaths = try container.decode([String].self, forKey: .imagePaths)
        logs = try container.decodeIfPresent([DreamLog].self, forKey: .logs) ?? []
        milestones = try container.decodeIfPresent([DreamStage].self, forKey: .milestones) ?? []
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        archivedAt = try container.decodeIfPresent(Date.self, forKey: .archivedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(visionText, forKey: .visionText)
        try container.encode(imagePaths, forKey: .imagePaths)
        try container.encode(logs, forKey: .logs)
        try container.encode(milestones, forKey: .milestones)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(isArchived, forKey: .isArchived)
        try container.encodeIfPresent(archivedAt, forKey: .archivedAt)
    }

    var sortedLogs: [DreamLog] {
        logs.sorted { $0.date > $1.date }
    }

    var latestLog: DreamLog? {
        sortedLogs.first
    }

    var todayLog: DreamLog? {
        logs.first { Calendar.current.isDateInToday($0.date) }
    }

    var hasLoggedToday: Bool {
        todayLog != nil
    }

    var totalDays: Int {
        Set(logs.map { Calendar.current.startOfDay(for: $0.date) }).count
    }

    var activeStageCount: Int {
        milestones.filter { !$0.isDone }.count
    }

    var completedStageCount: Int {
        milestones.filter(\.isDone).count
    }

    var evidenceCount: Int {
        logs.count + completedStageCount
    }

    var timelineItems: [DreamTimelineItem] {
        let logItems = logs.map(DreamTimelineItem.log)
        let stageItems = milestones
            .filter { $0.isDone }
            .map(DreamTimelineItem.stage)
        return (logItems + stageItems).sorted { $0.sortDate > $1.sortDate }
    }

    var moodScores: [(date: Date, score: Int)] {
        let oldestFirst = logs.sorted { $0.date < $1.date }
        var running = 0
        return oldestFirst.map { log in
            running += log.mood.score
            return (log.date, running)
        }
    }
}

enum DreamTimelineItem: Identifiable, Equatable {
    case log(DreamLog)
    case stage(DreamStage)

    var id: String {
        switch self {
        case .log(let log):
            return "log-\(log.id.uuidString)"
        case .stage(let stage):
            return "stage-\(stage.id.uuidString)"
        }
    }

    var sortDate: Date {
        switch self {
        case .log(let log):
            return log.date
        case .stage(let stage):
            return stage.doneAt ?? stage.createdAt
        }
    }
}

extension Dream {
    static let sample = Dream(
        title: "第一次马拉松",
        visionText: "冲过终点时，我能看见自己没有放弃的样子。",
        imagePaths: ["sample:marathon"],
        logs: [
            DreamLog(action: "快走 30 分钟，最后十分钟有点累，但没有停。", mood: .positive, date: Calendar.current.date(byAdding: .day, value: -4, to: Date()) ?? Date()),
            DreamLog(action: "下雨，只做了拉伸。接受这一步慢一点。", mood: .negative, date: Calendar.current.date(byAdding: .day, value: -3, to: Date()) ?? Date()),
            DreamLog(action: "完成 3 公里轻松跑，呼吸比上周稳。", mood: .positive, date: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())
        ],
        milestones: [
            DreamStage(title: "连续训练 7 天", targetDate: Calendar.current.date(byAdding: .day, value: 7, to: Date()))
        ]
    )
}
