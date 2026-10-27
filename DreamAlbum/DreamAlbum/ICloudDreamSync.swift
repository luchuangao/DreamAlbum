import Foundation

struct ICloudDreamBackup: Codable {
    var updatedAt: Date
    var dreams: [Dream]
    var backgroundStyle: AlbumBackgroundStyle
    var settingsDisplayStyle: SettingsDisplayStyle
    var timelineDisplayStyle: TimelineDisplayStyle
    var appLanguage: AppLanguage
    var isMoodChartEnabled: Bool
    var avatarImagePath: String
    var backgroundImageChoice: BackgroundImageChoice
    var customBackgroundImagePath: String?
    var backgroundContrast: BackgroundContrast

    init(
        updatedAt: Date,
        dreams: [Dream],
        backgroundStyle: AlbumBackgroundStyle,
        settingsDisplayStyle: SettingsDisplayStyle,
        timelineDisplayStyle: TimelineDisplayStyle = .timeline,
        appLanguage: AppLanguage,
        isMoodChartEnabled: Bool,
        avatarImagePath: String,
        backgroundImageChoice: BackgroundImageChoice = .worldSea,
        customBackgroundImagePath: String? = nil,
        backgroundContrast: BackgroundContrast = .regular
    ) {
        self.updatedAt = updatedAt
        self.dreams = dreams
        self.backgroundStyle = backgroundStyle
        self.settingsDisplayStyle = settingsDisplayStyle
        self.timelineDisplayStyle = timelineDisplayStyle
        self.appLanguage = appLanguage
        self.isMoodChartEnabled = isMoodChartEnabled
        self.avatarImagePath = avatarImagePath
        self.backgroundImageChoice = backgroundImageChoice
        self.customBackgroundImagePath = customBackgroundImagePath
        self.backgroundContrast = backgroundContrast
    }

    private enum CodingKeys: String, CodingKey {
        case updatedAt
        case dreams
        case backgroundStyle
        case settingsDisplayStyle
        case timelineDisplayStyle
        case appLanguage
        case isMoodChartEnabled
        case avatarImagePath
        case backgroundImageChoice
        case customBackgroundImagePath
        case backgroundContrast
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        dreams = try container.decode([Dream].self, forKey: .dreams)
        backgroundStyle = try container.decode(AlbumBackgroundStyle.self, forKey: .backgroundStyle)
        settingsDisplayStyle = try container.decode(SettingsDisplayStyle.self, forKey: .settingsDisplayStyle)
        timelineDisplayStyle = try container.decodeIfPresent(TimelineDisplayStyle.self, forKey: .timelineDisplayStyle) ?? .timeline
        appLanguage = try container.decode(AppLanguage.self, forKey: .appLanguage)
        isMoodChartEnabled = try container.decode(Bool.self, forKey: .isMoodChartEnabled)
        avatarImagePath = try container.decode(String.self, forKey: .avatarImagePath)
        backgroundImageChoice = try container.decodeIfPresent(BackgroundImageChoice.self, forKey: .backgroundImageChoice) ?? .worldSea
        customBackgroundImagePath = try container.decodeIfPresent(String.self, forKey: .customBackgroundImagePath)
        backgroundContrast = try container.decodeIfPresent(BackgroundContrast.self, forKey: .backgroundContrast) ?? .regular
    }
}

enum ICloudDreamSync {
    static let containerID = "iCloud.com.luchuangao.mengxiangxiangce"
    private static let backupFileName = "dream-album-backup.json"
    private static let imagesFolderName = "Images"

    static var containerURL: URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: containerID)
    }

    private static var documentsURL: URL? {
        containerURL?.appendingPathComponent("Documents", isDirectory: true)
    }

    private static var backupURL: URL? {
        documentsURL?.appendingPathComponent(backupFileName)
    }

    private static var imagesURL: URL? {
        documentsURL?.appendingPathComponent(imagesFolderName, isDirectory: true)
    }

    static func loadBackup() async -> ICloudDreamBackup? {
        guard let backupURL else { return nil }
        do {
            try await downloadIfNeeded(backupURL)
            let data = try Data(contentsOf: backupURL)
            return try JSONDecoder().decode(ICloudDreamBackup.self, from: data)
        } catch {
            return nil
        }
    }

    static func pushBackup(_ backup: ICloudDreamBackup) async {
        guard let documentsURL, let backupURL, let imagesURL else { return }
        do {
            try FileManager.default.createDirectory(at: documentsURL, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: imagesURL, withIntermediateDirectories: true)
            try copyReferencedImagesToCloud(paths: referencedImagePaths(in: backup), imagesURL: imagesURL)
            let data = try JSONEncoder().encode(backup)
            try data.write(to: backupURL, options: .atomic)
        } catch {
            return
        }
    }

    static func restoreImages(for backup: ICloudDreamBackup) async {
        guard let imagesURL else { return }
        let paths = referencedImagePaths(in: backup)
        for path in paths where !path.hasPrefix("sample:") {
            let localURL = ImageLibrary.documentsDirectory.appendingPathComponent(path)
            guard !FileManager.default.fileExists(atPath: localURL.path) else { continue }
            let cloudURL = imagesURL.appendingPathComponent(path)
            do {
                try await downloadIfNeeded(cloudURL)
                guard FileManager.default.fileExists(atPath: cloudURL.path) else { continue }
                try FileManager.default.copyItem(at: cloudURL, to: localURL)
            } catch {
                continue
            }
        }
    }

    private static func referencedImagePaths(in backup: ICloudDreamBackup) -> Set<String> {
        var paths = Set<String>()
        if !backup.avatarImagePath.isEmpty {
            paths.insert(backup.avatarImagePath)
        }
        if let path = backup.customBackgroundImagePath, !path.isEmpty {
            paths.insert(path)
        }
        for dream in backup.dreams {
            paths.formUnion(dream.imagePaths)
            for log in dream.logs {
                paths.formUnion(log.imagePaths)
            }
        }
        return paths
    }

    private static func copyReferencedImagesToCloud(paths: Set<String>, imagesURL: URL) throws {
        for path in paths where !path.hasPrefix("sample:") {
            let localURL = ImageLibrary.documentsDirectory.appendingPathComponent(path)
            guard FileManager.default.fileExists(atPath: localURL.path) else { continue }
            let cloudURL = imagesURL.appendingPathComponent(path)
            if FileManager.default.fileExists(atPath: cloudURL.path) {
                try? FileManager.default.removeItem(at: cloudURL)
            }
            try FileManager.default.copyItem(at: localURL, to: cloudURL)
        }
    }

    private static func downloadIfNeeded(_ url: URL) async throws {
        let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
        guard values?.ubiquitousItemDownloadingStatus != .current else { return }
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)

        for _ in 0..<20 {
            let status = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus
            if status == .current || FileManager.default.fileExists(atPath: url.path) {
                return
            }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
    }
}
