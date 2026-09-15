// Run with the service source; no live mounts, credentials, or network required.
import Foundation

@main
struct BucketMountChecks {
    static func main() throws {
        let mounts = try BucketMountService.parseStatus("""
        pid=123      bucket alice/checkpoints → /Volumes/Training Data
        pid=456      repo org/model → /Volumes/Model
        pid=789      bucket team/data → /private/tmp/données
        """)
        precondition(mounts.count == 2)
        precondition(mounts[0].pid == 123)
        precondition(mounts[0].mount.path == "/Volumes/Training Data")
        precondition(mounts[1].mount.bucket == "team/data")
        precondition(mounts[1].mount.path == "/private/tmp/données")
        let empty = try BucketMountService.parseStatus("No running daemons\n")
        precondition(empty.isEmpty)
        do {
            _ = try BucketMountService.parseStatus("pid=broken bucket alice/data → /tmp/data")
            fatalError("Malformed bucket status must not be silently accepted")
        } catch is BucketMountError {}

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let canonical = try BucketMountService.validateFolder(root.path)
        precondition(canonical == root.resolvingSymlinksInPath().path)
        try Data("keep me".utf8).write(to: root.appendingPathComponent("existing.txt"))
        do {
            _ = try BucketMountService.validateFolder(root.path)
            fatalError("Nonempty mount folders must be rejected")
        } catch is BucketMountError {}
        for path in ["/", "relative/path", root.appendingPathComponent("missing").path] {
            do {
                _ = try BucketMountService.validateFolder(path)
                fatalError("Invalid mount folder accepted: \(path)")
            } catch {}
        }
        let saved = BucketMount(bucket: "alice/data", path: canonical, readOnly: true, daemonPID: 123)
        let decoded = try JSONDecoder().decode(BucketMount.self, from: JSONEncoder().encode(saved))
        precondition(decoded == saved)
        print("Bucket mount checks passed: status parsing, folder validation, and saved settings.")
    }
}
