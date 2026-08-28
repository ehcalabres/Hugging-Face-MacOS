import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    private override init() {
        super.init()
    }

    func show(viewModel: DashboardViewModel) {
        if let window {
            AppWindowActivation.present(window, clearFirstResponder: true)
            return
        }

        let content = PreferencesView()
            .environmentObject(viewModel)
        let hostingView = NSHostingView(rootView: content)
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        window.title = "Hugging Face Settings"
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.delegate = self

        hostingView.layoutSubtreeIfNeeded()
        window.setContentSize(hostingView.fittingSize)
        window.updateConstraintsIfNeeded()
        window.center()

        self.window = window
        AppWindowActivation.present(window, clearFirstResponder: true)
    }

    func windowWillClose(_ notification: Notification) {
        AppWindowActivation.restoreAccessoryMode(afterClosing: notification.object as? NSWindow)
    }
}
