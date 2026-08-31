import Foundation

enum HuggingFacePreferences {
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
