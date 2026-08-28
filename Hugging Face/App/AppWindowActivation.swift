import AppKit

@MainActor
enum AppWindowActivation {
    static func present(_ window: NSWindow, clearFirstResponder: Bool = false) {
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        guard clearFirstResponder else { return }
        window.makeFirstResponder(nil)
        DispatchQueue.main.async { [weak window] in
            window?.makeFirstResponder(nil)
        }
    }

    static func restoreAccessoryMode(afterClosing closingWindow: NSWindow?) {
        DispatchQueue.main.async {
            let hasVisibleWindow = NSApp.windows.contains { window in
                window !== closingWindow
                    && window.isVisible
                    && window.styleMask.contains(.titled)
            }
            if !hasVisibleWindow {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}
