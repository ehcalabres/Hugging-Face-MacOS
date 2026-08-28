import Foundation

enum HuggingFacePreferences {
    static let namespaceKey = "jobsNamespace"
    static let showActiveCountKey = "showActiveJobCount"

    static var namespace: String? {
        let value = UserDefaults.standard
            .string(forKey: namespaceKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }
}
