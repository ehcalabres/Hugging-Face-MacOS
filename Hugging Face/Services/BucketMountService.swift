import Darwin
import Foundation

struct BucketMount: Identifiable, Codable, Equatable, Sendable {
    var id: String { path }
    let bucket: String
    let path: String
    var readOnly: Bool = false
    var daemonPID: Int32?
}

struct RunningBucketMount: Sendable {
    let mount: BucketMount
    let pid: Int32
}

enum BucketMountError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let message): message }
    }
}

enum BucketMountService {
    nonisolated static var executable: URL? {
        let directories = [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin").path,
            "/opt/homebrew/bin", "/usr/local/bin"
        ] + (ProcessInfo.processInfo.environment["PATH"] ?? "").components(separatedBy: ":")
        return directories.filter { !$0.isEmpty }.map {
            URL(fileURLWithPath: $0).appendingPathComponent("hf-mount")
        }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    // hf-mount status writes its records to stderr, including paths with spaces.
    nonisolated static func parseStatus(_ output: String) throws -> [RunningBucketMount] {
        let pattern = #"^pid=\s*(\d+)\s+bucket (\S+) → (/.+)$"#
        let regex = try NSRegularExpression(pattern: pattern)
        return try output.components(separatedBy: .newlines).compactMap { line in
            guard line.hasPrefix("pid="), line.contains(" bucket ") else { return nil }
            guard let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let pidRange = Range(match.range(at: 1), in: line),
                  let bucketRange = Range(match.range(at: 2), in: line),
                  let pathRange = Range(match.range(at: 3), in: line),
                  let pid = Int32(line[pidRange]) else {
                throw BucketMountError.message("Could not read hf-mount status. Check your installed hf-mount version.")
            }
            return RunningBucketMount(
                mount: BucketMount(bucket: String(line[bucketRange]), path: String(line[pathRange])), pid: pid
            )
        }
    }

    nonisolated static func mountedPaths() -> Set<String> {
        var entries: UnsafeMutablePointer<statfs>?
        let count = getmntinfo(&entries, MNT_NOWAIT)
        guard count > 0, let entries else { return [] }
        return Set((0..<Int(count)).map { index in
            var name = entries[index].f_mntonname
            return withUnsafePointer(to: &name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
            }
        })
    }

    nonisolated static func validateFolder(_ path: String) throws -> String {
        let url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        guard path.hasPrefix("/"), url.path != "/" else {
            throw BucketMountError.message("Choose an empty folder for the mount.")
        }
        guard !mountedPaths().contains(url.path) else {
            throw BucketMountError.message("That folder is already a mounted filesystem.")
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue,
              try FileManager.default.contentsOfDirectory(atPath: url.path).isEmpty else {
            throw BucketMountError.message("Choose an existing, empty folder so local files are not hidden by the mount.")
        }
        return url.path
    }

    nonisolated static func run(_ arguments: [String], token: String? = nil) async throws -> String {
        guard let executable else {
            throw BucketMountError.message("Install hf-mount to manage bucket mounts, then refresh this section.")
        }
        return try await Task.detached(priority: .userInitiated) {
            // A file avoids pipe-buffer deadlocks when the CLI prints daemon logs.
            let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            FileManager.default.createFile(atPath: outputURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
            defer { try? FileManager.default.removeItem(at: outputURL) }
            let output = try FileHandle(forWritingTo: outputURL)
            defer { try? output.close() }
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = [executable.deletingLastPathComponent().path, "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"].joined(separator: ":")
            if let token, !token.isEmpty { environment["HF_TOKEN"] = token }
            process.environment = environment
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = output
            process.standardError = output
            try process.run()
            let deadline = Date().addingTimeInterval(90)
            while process.isRunning && Date() < deadline {
                try await Task.sleep(for: .milliseconds(100))
            }
            guard !process.isRunning else {
                process.terminate()
                throw BucketMountError.message("hf-mount timed out. Refresh to check whether the mount is active; see ~/.hf-mount/logs for details.")
            }
            let input = try FileHandle(forReadingFrom: outputURL)
            defer { try? input.close() }
            let length = try input.seekToEnd()
            try input.seek(toOffset: process.terminationStatus != 0 && length > 32_768 ? length - 32_768 : 0)
            var text = String(decoding: try input.readToEnd() ?? Data(), as: UTF8.self)
            if let token, !token.isEmpty { text = text.replacingOccurrences(of: token, with: "[redacted]") }
            text = text.replacingOccurrences(of: #"hf_[A-Za-z0-9]+"#, with: "[redacted]", options: .regularExpression)
            guard process.terminationStatus == 0 else {
                throw BucketMountError.message(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "hf-mount failed (exit \(process.terminationStatus))." : text)
            }
            return text
        }.value
    }
}
