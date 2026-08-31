import Foundation
import UserNotifications

final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()

    private override init() {
        super.init()
        center.delegate = self
        if HuggingFacePreferences.notificationsEnabled {
            requestAuthorization()
        }
    }

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notifyJobTransition(from oldJob: Job?, to job: Job) {
        guard HuggingFacePreferences.notificationsEnabled else { return }

        let title: String
        if oldJob == nil {
            title = job.status == .running ? "Job started" : "New job"
        } else {
            title = switch job.status {
            case .running: "Job started"
            case .completed: "Job finished"
            case .error: "Job failed"
            case .canceled: "Job stopped"
            case .deleted: "Job deleted"
            case .scheduling: "Job queued"
            }
        }

        let previous = oldJob.map { "\($0.status.displayName) → " } ?? ""
        let detail = job.statusMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
        var body = "\(job.displayName): \(previous)\(job.status.displayName)"
        if let detail, !detail.isEmpty {
            body += "\n\(detail)"
        }
        deliver(title: title, body: body, identifier: "job.\(job.id).\(job.status.rawValue)")
    }

    func notifyEndpointTransition(from oldEndpoint: InferenceEndpoint?, to endpoint: InferenceEndpoint) {
        guard HuggingFacePreferences.notificationsEnabled else { return }

        let normalized = endpoint.status.state.lowercased().filter(\.isLetter)
        let title = switch normalized {
        case "running": "Endpoint started"
        case "paused", "stopped": "Endpoint stopped"
        case "scaledtozero": "Endpoint scaled to zero"
        case "failed", "error": "Endpoint failed"
        default: "Endpoint state changed"
        }
        let previous = oldEndpoint.map { "\(displayName(for: $0.status.state)) → " } ?? ""
        deliver(
            title: title,
            body: "\(endpoint.name): \(previous)\(displayName(for: endpoint.status.state))",
            identifier: "endpoint.\(endpoint.id).\(normalized)"
        )
    }

    private func displayName(for state: String) -> String {
        state
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }

    private func deliver(title: String, body: String, identifier: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
