import Combine
import Foundation

@MainActor
final class BucketsViewModel: ObservableObject {
    @Published private(set) var saved: [BucketMount] = []
    @Published private(set) var running: [RunningBucketMount] = []
    @Published private(set) var isBusy = false
    @Published private(set) var operation = ""
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var toolAvailable = false
    @Published var errorMessage: String?
    @Published var showsMountForm = false
    private let defaults: UserDefaults
    private let storageKey = "bucketMounts.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey) {
            saved = (try? JSONDecoder().decode([BucketMount].self, from: data)) ?? []
        }
    }

    var mounts: [BucketMount] {
        let active = running.map { daemon in
            saved.first { $0.path == daemon.mount.path && $0.bucket == daemon.mount.bucket } ?? daemon.mount
        }
        return (active + saved.filter { entry in !active.contains { $0.path == entry.path } })
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    func isMounted(_ mount: BucketMount) -> Bool {
        running.contains { $0.mount.path == mount.path && $0.mount.bucket == mount.bucket }
    }

    func isManaged(_ mount: BucketMount) -> Bool {
        saved.contains(mount) && (!isMounted(mount) || running.contains {
            $0.mount.path == mount.path && $0.pid == mount.daemonPID
        })
    }

    func refresh(clearError: Bool = true) async {
        guard !isBusy else { return }
        await perform("Refreshing mounts…", clearError: clearError) { try await self.reload() }
    }

    private func reload() async throws {
        toolAvailable = BucketMountService.executable != nil
        guard toolAvailable else { running = []; return }
        let result = try await BucketMountService.run(["status"])
        let activePaths = BucketMountService.mountedPaths()
        running = try BucketMountService.parseStatus(result).filter { activePaths.contains($0.mount.path) }
        lastUpdated = Date()
    }

    func mount(bucket: String, path: String, readOnly: Bool) async {
        guard !isBusy else { return }
        await perform("Mounting bucket…") {
            let bucket = bucket.trimmingCharacters(in: .whitespacesAndNewlines)
            guard bucket.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*$"#, options: .regularExpression) != nil else {
                throw BucketMountError.message("Enter a bucket ID in the form namespace/bucket-name.")
            }
            let canonicalPath = try await Task.detached { try BucketMountService.validateFolder(path) }.value
            let mount = BucketMount(bucket: bucket, path: canonicalPath, readOnly: readOnly)
            // Save before starting so a failed or timed-out mount remains recoverable.
            self.saved.removeAll { $0.path == canonicalPath }
            self.saved.append(mount)
            self.persist()
            try await self.start(mount)
            self.showsMountForm = false
        }
    }

    func unmount(_ mount: BucketMount) async {
        guard !isBusy else { return }
        await perform("Unmounting bucket…") {
            try await self.requireActive(mount)
            _ = try await BucketMountService.run(["stop", mount.path])
            try await self.reload()
            guard !self.isMounted(mount) else { throw BucketMountError.message("The bucket is still mounted. Close files using this folder and try again.") }
        }
    }

    func refreshMount(_ mount: BucketMount) async {
        guard !isBusy, isManaged(mount) else { return }
        await perform("Refreshing bucket mount…") {
            try await self.requireActive(mount)
            guard self.isManaged(mount) else {
                throw BucketMountError.message("This mount was replaced outside the app. Unmount it and mount it here to use saved settings.")
            }
            _ = try await BucketMountService.run(["stop", mount.path])
            _ = try await Task.detached { try BucketMountService.validateFolder(mount.path) }.value
            try await self.start(mount)
        }
    }

    private func requireActive(_ mount: BucketMount) async throws {
        try await reload()
        guard isMounted(mount) else { throw BucketMountError.message("This bucket is no longer mounted at that folder. The list has been refreshed.") }
    }

    private func start(_ mount: BucketMount) async throws {
        var arguments = ["start"]
        if mount.readOnly { arguments.append("--read-only") }
        arguments += ["bucket", mount.bucket, mount.path]
        _ = try await BucketMountService.run(arguments, token: KeychainService.loadToken())
        try await reload()
        guard isMounted(mount) else { throw BucketMountError.message("hf-mount finished, but the filesystem is not mounted. See ~/.hf-mount/logs for details.") }
        if let index = saved.firstIndex(where: { $0.path == mount.path }) {
            saved[index].daemonPID = running.first { $0.mount.path == mount.path }?.pid
            persist()
        }
    }

    func forget(_ mount: BucketMount) {
        guard !isBusy, !isMounted(mount) else { return }
        saved.removeAll { $0.path == mount.path }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: storageKey) }
    }

    private func perform(_ label: String, clearError: Bool = true, action: () async throws -> Void) async {
        isBusy = true
        operation = label
        if clearError { errorMessage = nil }
        defer { isBusy = false; operation = "" }
        do { try await action() }
        catch {
            errorMessage = error.localizedDescription
            try? await reload()
        }
    }
}
