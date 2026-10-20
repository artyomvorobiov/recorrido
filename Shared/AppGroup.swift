import Foundation

/// The app group shared by the app and the widget extension.
///
/// Its id comes from Info.plist (`RecorridoAppGroup`, filled from the
/// `APP_GROUP_ID` build setting). Without the entitlement — for example with
/// a free developer account — everything keeps working with private storage;
/// the widget then shows the route of the day instead of the active walk.
enum AppGroup {
    static let identifier: String? = {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "RecorridoAppGroup") as? String,
              !value.isEmpty, !value.contains("$(") else { return nil }
        return value
    }()

    static let containerURL: URL? = {
        guard let identifier else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }()

    static var isAvailable: Bool { containerURL != nil }

    static let storage: StorageLayout = {
        let base = containerURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return StorageLayout(directory: base.appendingPathComponent("Recorrido", isDirectory: true))
    }()

    static let defaults: UserDefaults = {
        if containerURL != nil, let identifier, let shared = UserDefaults(suiteName: identifier) {
            return shared
        }
        return .standard
    }()
}

enum SettingsKey {
    static let contentLanguage = "contentLanguage"
    static let speechRate = "speechRate"
    static let autoPlay = "autoPlayOnArrival"
    static let backgroundTracking = "backgroundTracking"
    static let arrivalNotifications = "arrivalNotifications"

    static func registerDefaults() {
        AppGroup.defaults.register(defaults: [
            contentLanguage: "auto",
            speechRate: 1.0,
            autoPlay: true,
            backgroundTracking: true,
            arrivalNotifications: true,
        ])
    }
}

/// Language of route texts and Wikipedia content: Russian or English.
enum ContentLanguage {
    static let supported = ["ru", "en"]

    static var current: String {
        let setting = AppGroup.defaults.string(forKey: SettingsKey.contentLanguage) ?? "auto"
        if supported.contains(setting) { return setting }
        let preferred = Locale.preferredLanguages.first ?? "en"
        let russianSpeaking = ["ru", "uk", "be", "kk", "ky", "uz", "hy", "ka", "az", "tg"]
        return russianSpeaking.contains { preferred.hasPrefix($0) } ? "ru" : "en"
    }
}

/// Reads the curated city files bundled with the app (and the widget).
enum CatalogLoader {
    static func bundledFiles(in bundle: Bundle = .main) -> [URL] {
        var files: [String: URL] = [:]
        for subdirectory in [nil, "Catalog"] as [String?] {
            for url in bundle.urls(forResourcesWithExtension: "json", subdirectory: subdirectory) ?? [] {
                if url.lastPathComponent.hasPrefix("city-") {
                    files[url.lastPathComponent] = url
                }
            }
        }
        return Array(files.values)
    }

    static func load(language: String = ContentLanguage.current) -> Catalog {
        Catalog.load(files: bundledFiles(), language: language) { url, error in
            print("Recorrido: cannot read \(url.lastPathComponent): \(error)")
        }
    }
}
