import AppKit
import SwiftUI

struct BucketsView: View {
    @ObservedObject var model: BucketsViewModel
    @State private var bucket = ""
    @State private var folder = ""
    @State private var readOnly = false
    @State private var pendingAction: MountAction?

    private struct MountAction: Identifiable {
        let mount: BucketMount
        let refresh: Bool
        var id: String { mount.id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let error = model.errorMessage {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(error).font(.caption).textSelection(.enabled)
                        Button("Dismiss") { model.errorMessage = nil }.font(.caption)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }

                if !model.toolAvailable {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Install hf-mount", systemImage: "externaldrive.badge.plus")
                            .font(.headline)
                        Text("Buckets use hf-mount to appear as folders on your Mac. Install it, then refresh to get started.")
                            .font(.caption).foregroundStyle(.secondary)
                        Link("Installation instructions", destination: URL(string: "https://github.com/huggingface/hf-mount#install")!)
                            .font(.caption)
                    }
                }

                HStack {
                    Text("Buckets on this Mac").font(.subheadline.weight(.semibold))
                    Spacer()
                    Button("Mount bucket…") { model.showsMountForm.toggle() }
                        .disabled(!model.toolAvailable || model.isBusy)
                }

                if model.showsMountForm { mountForm }

                if model.isBusy {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(model.operation).font(.caption).foregroundStyle(.secondary)
                    }
                }

                if model.mounts.isEmpty && !model.showsMountForm {
                    VStack(spacing: 8) {
                        Image(systemName: "externaldrive").font(.title2).foregroundStyle(.secondary)
                        Text("No bucket mounts yet").font(.subheadline.weight(.medium))
                        Text("Mount an existing bucket in an empty folder. Buckets mounted with hf-mount also appear here.")
                            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 24)
                }

                ForEach(model.mounts) { mount in mountRow(mount) }

                Text("Mounted buckets sync changes automatically. Refresh & sync remounts buckets configured here; close open files first. Mounts stay active when you quit the app.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(14)
        }
        .frame(minHeight: 260, maxHeight: 560)
        .task {
            await model.refresh()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
                await model.refresh(clearError: false)
            }
        }
        .alert(item: $pendingAction) { action in
            Alert(
                title: Text(action.refresh ? "Refresh & sync bucket?" : "Unmount bucket?"),
                message: Text(action.refresh
                    ? "Close files using \(action.mount.path). The bucket will briefly unmount, then reconnect using its saved settings."
                    : "Close files using \(action.mount.path) before unmounting. The bucket and its remote files will be kept."),
                primaryButton: .default(Text(action.refresh ? "Refresh & sync" : "Unmount")) {
                    Task {
                        if action.refresh { await model.refreshMount(action.mount) }
                        else { await model.unmount(action.mount) }
                    }
                },
                secondaryButton: .cancel()
            )
        }
    }

    private var mountForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("namespace/bucket-name", text: $bucket)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Bucket ID")
            HStack {
                Text(folder.isEmpty ? "Choose an empty folder" : folder)
                    .font(.caption).lineLimit(2).truncationMode(.middle)
                Spacer()
                Button("Choose…") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.canCreateDirectories = true
                    panel.allowsMultipleSelection = false
                    panel.prompt = "Choose mount folder"
                    NSApp.activate(ignoringOtherApps: true)
                    panel.begin { response in
                        if response == .OK, let url = panel.url { folder = url.path }
                    }
                }
            }
            Toggle("Read-only", isOn: $readOnly).font(.caption)
            Text("Uses the token in Settings, or HF_TOKEN if available.")
                .font(.caption2).foregroundStyle(.secondary)
            HStack {
                Button("Cancel") { model.showsMountForm = false }
                Spacer()
                Button("Mount") {
                    Task { await model.mount(bucket: bucket, path: folder, readOnly: readOnly) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(bucket.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || folder.isEmpty)
            }
        }
        .disabled(model.isBusy)
        .padding(10)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
    }

    private func mountRow(_ mount: BucketMount) -> some View {
        let active = model.isMounted(mount)
        let managed = model.isManaged(mount)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "externaldrive").foregroundStyle(active ? .green : .secondary)
                Text(mount.bucket).font(.subheadline.weight(.medium)).lineLimit(1).help(mount.bucket)
                Spacer()
                Text(active ? "Mounted" : "Unmounted")
                    .font(.caption2).foregroundStyle(active ? .green : .secondary)
            }
            Text(mount.path).font(.caption).foregroundStyle(.secondary)
                .lineLimit(2).truncationMode(.middle).textSelection(.enabled)
            HStack(spacing: 10) {
                if active {
                    Button("Open folder") { NSWorkspace.shared.open(URL(fileURLWithPath: mount.path)) }
                    if managed {
                        Button("Refresh & sync") { pendingAction = MountAction(mount: mount, refresh: true) }
                    }
                    Spacer(minLength: 0)
                    Button("Unmount") { pendingAction = MountAction(mount: mount, refresh: false) }
                } else {
                    Button("Mount") {
                        Task { await model.mount(bucket: mount.bucket, path: mount.path, readOnly: mount.readOnly) }
                    }
                    Spacer()
                    Button("Forget") { model.forget(mount) }
                        .help("Remove this saved mount from the list. No files are deleted.")
                }
            }
            .font(.caption).buttonStyle(.borderless)
            .disabled(model.isBusy || !model.toolAvailable)
            if !managed {
                Text("Mounted outside the app · syncs automatically")
                    .font(.caption2).foregroundStyle(.secondary)
            } else if mount.readOnly {
                Text("Read-only").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
    }
}
