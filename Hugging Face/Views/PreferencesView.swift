//
//  PreferencesView.swift
//  Hugging Face
//
//  Created by Enrique Hernández Calabrés on 05/08/2026.
//

import AppKit
import ServiceManagement
import SwiftUI

private struct SettingRow<Control: View>: View {
    let title: String
    let description: String
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            control()
                .controlSize(.small)
                .frame(width: 220, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }
}

struct PreferencesView: View {
    @EnvironmentObject private var vm: DashboardViewModel
    @AppStorage(HuggingFacePreferences.namespaceKey) private var namespace = ""
    @AppStorage(HuggingFacePreferences.showActiveCountKey) private var showActiveCount = true
    @AppStorage(HuggingFacePreferences.notificationsEnabledKey) private var notificationsEnabled = true
    @AppStorage(HuggingFacePreferences.compactDashboardKey) private var compactDashboard = false

    @State private var token = KeychainService.loadToken() ?? ""
    @State private var poll: Double = 30
    @State private var jobsPerSection = 5
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var showingTokenSheet = false
    @State private var isTesting = false
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var launchAtLoginError: String?
    @FocusState private var namespaceIsFocused: Bool

    private let pollingOptions: [(value: Double, label: String)] = [
        (15, "15 seconds"),
        (30, "30 seconds"),
        (60, "1 minute"),
        (300, "5 minutes")
    ]

    var body: some View {
        Form {
            Section {
                SettingRow(
                    title: "Launch at login",
                    description: "Keep Hugging Face app available in the menu bar after signing in."
                ) {
                    HStack(spacing: 7) {
                        if let launchAtLoginError {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.red)
                                .help(launchAtLoginError)
                        }

                        Toggle(
                            "",
                            isOn: Binding(
                                get: { launchAtLogin },
                                set: { updateLaunchAtLogin($0) }
                            )
                        )
                        .labelsHidden()
                    }
                }
            }

            Section {
                SettingRow(
                    title: "Hugging Face token",
                    description: "Used securely for authenticated API requests."
                ) {
                    Button(token.isEmpty ? "Set…" : abbreviatedToken) {
                        showingTokenSheet = true
                    }
                    .font(.callout)
                }

                SettingRow(
                    title: "Namespace",
                    description: "Leave blank for your account, or enter an organization name."
                ) {
                    HStack(spacing: 6) {
                        if !namespace.isEmpty {
                            Button {
                                namespace = ""
                                namespaceIsFocused = false
                                Task { await vm.refresh() }
                            } label: {
                                Image(systemName: "arrow.counterclockwise")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Use your personal namespace")
                        }

                        TextField("Personal account", text: $namespace)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 170)
                            .focused($namespaceIsFocused)
                            .onSubmit {
                                commitNamespace()
                            }

                        if namespaceIsFocused {
                            Button {
                                commitNamespace()
                            } label: {
                                Image(systemName: "checkmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .help("Finish editing")
                        }
                    }
                }

                SettingRow(
                    title: "Connection",
                    description: "Check the token and selected namespace against Hugging Face."
                ) {
                    HStack(spacing: 8) {
                        if let statusMessage {
                            Label(statusMessage, systemImage: statusIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                                .labelStyle(.titleAndIcon)
                                .font(.system(size: 11))
                                .foregroundStyle(statusIsError ? .red : .green)
                                .lineLimit(1)
                        }

                        Button(isTesting ? "Testing…" : "Test") {
                            Task { await testConnection() }
                        }
                        .disabled(isTesting || token.isEmpty)
                    }
                }
            }

            Section {
                SettingRow(
                    title: "Automatic refresh",
                    description: "Keep Jobs, Endpoints, and Inference Providers usage updated on a schedule."
                ) {
                    Toggle("", isOn: $vm.automaticRefreshEnabled)
                        .labelsHidden()
                        .onChange(of: vm.automaticRefreshEnabled) { _, _ in
                            vm.start()
                        }
                }

                SettingRow(
                    title: "Refresh interval",
                    description: "How often to check for status changes."
                ) {
                    Picker("", selection: $poll) {
                        ForEach(pollingOptions, id: \.value) { option in
                            Text(option.label).tag(option.value)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 125)
                    .disabled(!vm.automaticRefreshEnabled)
                    .onChange(of: poll) { _, value in
                        vm.pollInterval = value
                        vm.start()
                    }
                }

                SettingRow(
                    title: "Items per section",
                    description: "Number of Jobs, schedules, and Endpoints shown before the Show More control."
                ) {
                    Picker("", selection: $jobsPerSection) {
                        ForEach(displayLimitOptions, id: \.self) { value in
                            Text("\(value)").tag(value)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 70)
                    .onChange(of: jobsPerSection) { _, value in
                        vm.displayLimit = value
                    }
                }

                SettingRow(
                    title: "Activity counts",
                    description: "Show the combined number of active Jobs, schedules, and Endpoints beside the menu icon."
                ) {
                    Toggle("", isOn: $showActiveCount)
                        .labelsHidden()
                }

                SettingRow(
                    title: "Compact dashboard",
                    description: "Show only state, name, and actions for Jobs, schedules, and Endpoints."
                ) {
                    Toggle("", isOn: $compactDashboard)
                        .labelsHidden()
                }

                SettingRow(
                    title: "State change notifications",
                    description: "Notify when Jobs and Endpoints start, stop, finish, fail, or scale to zero."
                ) {
                    Toggle("", isOn: $notificationsEnabled)
                        .labelsHidden()
                        .onChange(of: notificationsEnabled) { _, enabled in
                            HuggingFacePreferences.notificationsEnabled = enabled
                            if enabled {
                                NotificationService.shared.requestAuthorization()
                            }
                        }
                }
            }

            Section {
                footer
                    .listRowBackground(Color.clear)
            }
        }
        .formStyle(.grouped)
        .frame(width: 620)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            poll = nearestPollingOption(to: vm.pollInterval)
            jobsPerSection = vm.displayLimit
            namespaceIsFocused = false
        }
        .onDisappear {
            namespace = namespace.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .sheet(isPresented: $showingTokenSheet) {
            TokenSheet(token: token) { newToken in
                token = newToken
                showingTokenSheet = false
                statusMessage = nil
                Task { await testConnection() }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("Hugging Face \(appVersion)")

            Spacer()

            Button {
                NSWorkspace.shared.open(URL(string: "https://huggingface.co/docs/hub/jobs")!)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "book")
                    Text("Jobs documentation")
                }
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }

    private var displayLimitOptions: [Int] {
        Array(Set([3, 5, 10, 20, vm.displayLimit])).sorted()
    }

    private var abbreviatedToken: String {
        guard token.count > 8 else { return "Saved…" }
        return "\(token.prefix(3))…\(token.suffix(4))"
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private func nearestPollingOption(to value: Double) -> Double {
        pollingOptions.min { abs($0.value - value) < abs($1.value - value) }?.value ?? 30
    }

    private func commitNamespace() {
        namespace = namespace.trimmingCharacters(in: .whitespacesAndNewlines)
        namespaceIsFocused = false
        Task { await vm.refresh() }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = enabled
            launchAtLoginError = nil
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            launchAtLoginError = error.localizedDescription
        }
    }

    private func testConnection() async {
        guard !token.isEmpty else { return }

        isTesting = true
        defer { isTesting = false }

        await vm.refresh()
        if let error = vm.errorMessage {
            statusMessage = error
            statusIsError = true
        } else {
            statusMessage = "Connected"
            statusIsError = false
        }
    }
}

private struct TokenSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var token: String

    let onSave: (String) -> Void

    init(token: String, onSave: @escaping (String) -> Void) {
        _token = State(initialValue: token)
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Hugging Face Token")
                    .font(.headline)
                Text("The token needs permission to read and manage Jobs in the selected namespace.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            SecureField("hf_…", text: $token)
                .textContentType(.password)

            HStack {
                Link("Create a token", destination: URL(string: "https://huggingface.co/settings/tokens")!)
                    .font(.callout)

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 430)
    }

    private func save() {
        let cleaned = token.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if cleaned.isEmpty {
                try KeychainService.deleteToken()
            } else {
                try KeychainService.saveToken(cleaned)
            }
            onSave(cleaned)
        } catch {
            NSSound.beep()
        }
    }
}
