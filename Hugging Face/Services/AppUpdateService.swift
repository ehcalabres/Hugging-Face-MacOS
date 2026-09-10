import AppKit
import Combine
import SwiftUI

@MainActor
final class AppUpdateService: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = AppUpdateService()
    static let intervalKey = "appUpdateIntervalHours"
    static let lastCheckKey = "appUpdateLastCheck"
    static let intervals = [6, 12, 24, 48, 168]

    @Published var intervalHours: Int {
        didSet {
            UserDefaults.standard.set(intervalHours, forKey: Self.intervalKey)
            checkIfDue()
        }
    }
    @Published private(set) var isChecking = false
    @Published private(set) var isInstalling = false
    @Published private(set) var release: AppRelease?
    @Published private(set) var message = ""
    @Published private(set) var lastCheck: Date?
    private var timer: Timer?
    private var window: NSWindow?

    private override init() {
        let saved = UserDefaults.standard.object(forKey: Self.intervalKey) as? Int ?? 24
        intervalHours = Self.intervals.contains(saved) || saved == 0 ? saved : 24
        lastCheck = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date
        super.init()
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.checkIfDue() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil
        )
        checkIfDue()
    }

    @objc private func didWake() { checkIfDue() }

    private func checkIfDue() {
        guard intervalHours > 0, !isChecking, !isInstalling,
              lastCheck == nil || Date().timeIntervalSince(lastCheck!) >= Double(intervalHours) * 3600 else { return }
        Task { await check() }
    }

    func check(manual: Bool = false) async {
        guard !isChecking, !isInstalling else { return }
        isChecking = true
        message = "Checking for updates…"
        // Persist attempts too, so offline launches and rate limits do not cause request loops.
        lastCheck = Date()
        UserDefaults.standard.set(lastCheck, forKey: Self.lastCheckKey)
        defer { isChecking = false }
        do {
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/ehcalabres/Hugging-Face-MacOS/releases/latest")!)
            request.timeoutInterval = 30
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Hugging-Face-macOS-Updater", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw UpdateError("Invalid release response.") }
            if http.statusCode == 404 {
                release = nil
                message = "No published release is available yet."
            } else {
                guard http.statusCode == 200 else { throw UpdateError("Could not check for updates (HTTP \(http.statusCode)). Try again later.") }
                let latest = try JSONDecoder().decode(AppRelease.self, from: data)
                guard let version = latest.version,
                      let current = ReleaseVersion(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") else {
                    throw UpdateError("The release version could not be read.")
                }
                if !latest.draft && !latest.prerelease && version > current {
                    guard latest.installAssets != nil else { throw UpdateError("The latest release is missing its update image or checksum. Try again later.") }
                    release = latest
                    message = "Hugging Face \(version.description) is available."
                    showWindow()
                } else {
                    release = nil
                    message = "You’re up to date."
                }
            }
        } catch {
            message = error.localizedDescription
        }
        if manual { showWindow() }
    }

    func showWindow() {
        if window == nil {
            let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Software Update"
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: AppUpdateView(updater: self))
            window.setContentSize(NSSize(width: 480, height: 380))
            window.center()
            self.window = window
        }
        AppWindowActivation.present(window!)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { !isInstalling }

    func windowWillClose(_ notification: Notification) {
        AppWindowActivation.restoreAccessoryMode(afterClosing: notification.object as? NSWindow)
    }

    func dismiss() { window?.performClose(nil) }

    func install() async {
        guard !isInstalling, let release, let assets = release.installAssets, let version = release.version else { return }
        isInstalling = true
        message = "Downloading and verifying the update…"
        defer { isInstalling = false }
        let manager = FileManager.default
        let work = manager.temporaryDirectory.appendingPathComponent("hugging-face-update-\(UUID().uuidString)", isDirectory: true)
        do {
            guard let source = Bundle.main.url(forResource: "install-update", withExtension: "sh") else {
                throw UpdateError("The update script is missing. Reinstall from GitHub Releases.")
            }
            let target = Bundle.main.bundleURL.resolvingSymlinksInPath()
            guard !target.path.contains("/AppTranslocation/"), !target.path.hasPrefix("/Volumes/"),
                  manager.isWritableFile(atPath: target.path),
                  manager.isWritableFile(atPath: target.deletingLastPathComponent().path) else {
                throw UpdateError("Move Hugging Face to a writable Applications folder before updating. You can also install the latest release manually.")
            }
            try manager.createDirectory(at: work, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let script = work.appendingPathComponent("install-update.sh")
            try manager.copyItem(at: source, to: script)
            let logs = manager.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs/Hugging Face", isDirectory: true)
            try manager.createDirectory(at: logs, withIntermediateDirectories: true)
            let log = logs.appendingPathComponent("Update.log")
            manager.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600])
            let output = try FileHandle(forWritingTo: log)
            defer { try? output.close() }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [script.path, work.path, target.path, String(ProcessInfo.processInfo.processIdentifier), version.description, assets.image.absoluteString, assets.checksum.absoluteString]
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = output
            process.standardError = output
            try process.run()
            let ready = work.appendingPathComponent("ready")
            while process.isRunning {
                if manager.fileExists(atPath: ready.path) {
                    message = "Restarting to install the update…"
                    NSApp.terminate(nil)
                    return
                }
                try await Task.sleep(for: .milliseconds(250))
            }
            throw UpdateError("The update could not be installed. Your current app is unchanged. See ~/Library/Logs/Hugging Face/Update.log for details, or install from GitHub Releases.")
        } catch {
            message = error.localizedDescription
            try? manager.removeItem(at: work)
        }
    }
}

private struct UpdateError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
