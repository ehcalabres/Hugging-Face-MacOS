import AppKit
import SwiftUI

@MainActor
final class JobLogsWindowController: NSObject, NSWindowDelegate {
    static let shared = JobLogsWindowController()

    private var windows: [String: NSWindow] = [:]

    private override init() {
        super.init()
    }

    func show(
        jobID: String,
        owner: String,
        title: String,
        isTerminal: Bool,
        viewModel: DashboardViewModel
    ) {
        if let window = windows[jobID] {
            AppWindowActivation.present(window)
            return
        }

        let content = JobDetailView(
            jobID: jobID,
            owner: owner,
            jobTitle: title,
            isTerminal: isTerminal,
            dashboardViewModel: viewModel
        )
        let hostingView = NSHostingView(rootView: content)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Job — \(title)"
        window.contentView = hostingView
        window.minSize = NSSize(width: 660, height: 620)
        window.isReleasedWhenClosed = false
        window.identifier = NSUserInterfaceItemIdentifier(jobID)
        window.delegate = self
        window.center()

        windows[jobID] = window
        AppWindowActivation.present(window)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        windows = windows.filter { $0.value !== window }
        AppWindowActivation.restoreAccessoryMode(afterClosing: window)
    }
}
