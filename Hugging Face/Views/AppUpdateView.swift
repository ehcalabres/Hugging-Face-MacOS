import SwiftUI

struct AppUpdateView: View {
    @ObservedObject var updater: AppUpdateService

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(updater.release == nil ? "Software Update" : "A new version is available")
                .font(.title2.bold())
            Text(updater.message)
                .font(.callout)
                .textSelection(.enabled)
            if updater.isInstalling || updater.isChecking {
                ProgressView().controlSize(.small)
            }
            if let release = updater.release {
                Text("Installing will quit and reopen Hugging Face.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                ScrollView {
                    Text(release.body?.isEmpty == false ? release.body! : "This release includes improvements to Hugging Face.")
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Spacer(minLength: 0)
            HStack {
                Link("GitHub Releases", destination: URL(string: "https://github.com/ehcalabres/Hugging-Face-MacOS/releases")!)
                Spacer()
                Button(updater.release == nil ? "Close" : "Later") { updater.dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(updater.isInstalling)
                if updater.release != nil {
                    Button("Install and Restart") { Task { await updater.install() } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(updater.isInstalling || updater.isChecking)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
