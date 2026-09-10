import Foundation

enum HuggingFacePreferences {
    // Direct-download releases no longer use App Sandbox. Import existing settings once.
    static func migrateSandboxPreferences() {
        let defaults = UserDefaults.standard
        let marker = "didMigrateSandboxPreferences"
        guard !defaults.bool(forKey: marker), let identifier = Bundle.main.bundleIdentifier else { return }
        let oldURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/\(identifier)/Data/Library/Preferences/\(identifier).plist")
        if let data = try? Data(contentsOf: oldURL),
           let values = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] {
            let existing = defaults.persistentDomain(forName: identifier) ?? [:]
            for (key, value) in values where existing[key] == nil {
                defaults.set(value, forKey: key)
            }
        }
        defaults.set(true, forKey: marker)
    }

    static let namespaceKey = "jobsNamespace"
    static let showActiveCountKey = "showActiveJobCount"
    static let notificationsEnabledKey = "stateChangeNotificationsEnabled"
    static let compactDashboardKey = "compactDashboardRows"

    static var notificationsEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: notificationsEnabledKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: notificationsEnabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: notificationsEnabledKey) }
    }

    static var namespace: String? {
        let value = UserDefaults.standard
            .string(forKey: namespaceKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }
}
