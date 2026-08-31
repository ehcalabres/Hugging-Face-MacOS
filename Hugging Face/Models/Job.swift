//
//  Job.swift
//  Hugging Face
//
//  Created by Enrique Hernández Calabrés on 05/08/2026.
//

import Foundation

struct Job: Decodable, Identifiable, Equatable, Sendable {
    enum Status: String, Decodable, CaseIterable, Sendable {
        case scheduling = "SCHEDULING"
        case running = "RUNNING"
        case completed = "COMPLETED"
        case error = "ERROR"
        case canceled = "CANCELED"
        case deleted = "DELETED"

        var displayName: String {
            switch self {
            case .scheduling: "Queued"
            case .running: "Running"
            case .completed: "Completed"
            case .error: "Failed"
            case .canceled: "Canceled"
            case .deleted: "Deleted"
            }
        }

        var isActive: Bool {
            self == .scheduling || self == .running
        }
    }

    struct Owner: Decodable, Equatable, Sendable {
        let name: String
    }

    private struct StatusPayload: Decodable {
        let stage: Status
        let message: String?
    }

    let id: String
    let createdAt: Date
    let startedAt: Date?
    let finishedAt: Date?
    let dockerImage: String?
    let spaceId: String?
    let command: [String]?
    let arguments: [String]?
    let flavor: String
    let owner: Owner
    let labels: [String: String]?
    let status: Status
    let statusMessage: String?

    var name: String? {
        labels?["name"]?.nilIfEmpty
    }

    var displayName: String {
        name
            ?? spaceId?.nilIfEmpty
            ?? dockerImage?.nilIfEmpty
            ?? command?.first?.nilIfEmpty
            ?? id
    }

    var detail: String {
        if let command, !command.isEmpty {
            return (command + (arguments ?? [])).joined(separator: " ")
        }
        return spaceId ?? dockerImage ?? id
    }

    var webURL: URL? {
        URL(string: "https://huggingface.co")?
            .appending(path: "jobs")
            .appending(path: owner.name)
            .appending(path: id)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case startedAt
        case finishedAt
        case dockerImage
        case spaceId
        case command
        case arguments
        case flavor
        case owner
        case labels
        case status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let statusPayload = try container.decode(StatusPayload.self, forKey: .status)

        id = try container.decode(String.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        finishedAt = try container.decodeIfPresent(Date.self, forKey: .finishedAt)
        dockerImage = try container.decodeIfPresent(String.self, forKey: .dockerImage)
        spaceId = try container.decodeIfPresent(String.self, forKey: .spaceId)
        command = try container.decodeIfPresent([String].self, forKey: .command)
        arguments = try container.decodeIfPresent([String].self, forKey: .arguments)
        flavor = try container.decode(String.self, forKey: .flavor)
        owner = try container.decode(Owner.self, forKey: .owner)
        labels = try container.decodeIfPresent([String: String].self, forKey: .labels)
        status = statusPayload.stage
        statusMessage = statusPayload.message
    }
}

struct JobMetrics: Decodable, Equatable, Sendable {
    struct GPU: Equatable, Sendable, Identifiable {
        let name: String
        let utilization: Double?
        let memoryUtilization: Double?
        let memoryUsedBytes: Int64?
        let memoryTotalBytes: Int64?
        let temperature: Double?

        var id: String { name }

        fileprivate init(name: String, payload: GPUPayload) {
            self.name = name
            utilization = payload.utilization
            memoryUtilization = payload.memoryUtilization
            memoryUsedBytes = payload.memoryUsedBytes
            memoryTotalBytes = payload.memoryTotalBytes
            temperature = payload.temperature
        }
    }

    fileprivate struct GPUPayload: Decodable, Equatable, Sendable {
        let utilization: Double?
        let memoryUtilization: Double?
        let memoryUsedBytes: Int64?
        let memoryTotalBytes: Int64?
        let temperature: Double?

        private enum CodingKeys: String, CodingKey {
            case utilization = "gpu_utilization"
            case memoryUtilization = "memory_utilization"
            case memoryUsedBytes = "memory_used_bytes"
            case memoryTotalBytes = "memory_total_bytes"
            case temperature
        }
    }

    let cpuUsagePercent: Double
    let cpuMillicores: Int
    let memoryUsedBytes: Int64
    let memoryTotalBytes: Int64
    let receivedBytesPerSecond: Int64
    let transmittedBytesPerSecond: Int64
    let replica: String
    let gpus: [GPU]

    var memoryUsagePercent: Double {
        guard memoryTotalBytes > 0 else { return 0 }
        return Double(memoryUsedBytes) / Double(memoryTotalBytes) * 100
    }

    private enum CodingKeys: String, CodingKey {
        case cpuUsagePercent = "cpu_usage_pct"
        case cpuMillicores = "cpu_millicores"
        case memoryUsedBytes = "memory_used_bytes"
        case memoryTotalBytes = "memory_total_bytes"
        case receivedBytesPerSecond = "rx_bps"
        case transmittedBytesPerSecond = "tx_bps"
        case replica
        case gpus
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cpuUsagePercent = try container.decode(Double.self, forKey: .cpuUsagePercent)
        cpuMillicores = try container.decode(Int.self, forKey: .cpuMillicores)
        memoryUsedBytes = try container.decode(Int64.self, forKey: .memoryUsedBytes)
        memoryTotalBytes = try container.decode(Int64.self, forKey: .memoryTotalBytes)
        receivedBytesPerSecond = try container.decode(Int64.self, forKey: .receivedBytesPerSecond)
        transmittedBytesPerSecond = try container.decode(Int64.self, forKey: .transmittedBytesPerSecond)
        replica = try container.decode(String.self, forKey: .replica)
        let payloads = try container.decodeIfPresent([String: GPUPayload].self, forKey: .gpus) ?? [:]
        gpus = payloads.map { GPU(name: $0.key, payload: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

struct ScheduledJob: Decodable, Identifiable, Equatable, Sendable {
    struct JobSpec: Decodable, Equatable, Sendable {
        let dockerImage: String?
        let spaceId: String?
        let command: [String]?
        let arguments: [String]?
        let flavor: String?
        let labels: [String: String]?
    }

    struct LastJob: Decodable, Equatable, Sendable {
        let id: String
        let at: Date
    }

    struct Status: Decodable, Equatable, Sendable {
        let lastJob: LastJob?
        let nextJobRunAt: Date?
    }

    let id: String
    let createdAt: Date
    let jobSpec: JobSpec
    let schedule: String?
    let suspend: Bool?
    let concurrency: Bool?
    let status: Status
    let owner: Job.Owner

    var isSuspended: Bool { suspend == true }

    var displayName: String {
        jobSpec.labels?["name"]?.nilIfEmpty
            ?? jobSpec.spaceId?.nilIfEmpty
            ?? jobSpec.dockerImage?.nilIfEmpty
            ?? jobSpec.command?.first?.nilIfEmpty
            ?? id
    }

    var detail: String {
        if let command = jobSpec.command, !command.isEmpty {
            return (command + (jobSpec.arguments ?? [])).joined(separator: " ")
        }
        return jobSpec.spaceId ?? jobSpec.dockerImage ?? id
    }
}

struct InferenceEndpoint: Decodable, Identifiable, Equatable, Sendable {
    struct Model: Decodable, Equatable, Sendable {
        let repository: String
        let framework: String?
        let revision: String?
        let task: String?
    }

    struct Compute: Decodable, Equatable, Sendable {
        struct Scaling: Decodable, Equatable, Sendable {
            let minReplica: Int?
            let maxReplica: Int?
            let scaleToZeroTimeout: Int?
        }

        let accelerator: String?
        let instanceSize: String?
        let instanceType: String?
        let scaling: Scaling?
    }

    struct Provider: Decodable, Equatable, Sendable {
        let vendor: String?
        let region: String?
    }

    struct Status: Decodable, Equatable, Sendable {
        let state: String
        let url: URL?
        let createdAt: Date?
        let updatedAt: Date?
        let message: String?
    }

    let name: String
    let type: String?
    let model: Model
    let compute: Compute?
    let provider: Provider?
    let status: Status

    var id: String { name }
    var isPaused: Bool { status.state.lowercased() == "paused" }
    var isRunning: Bool { status.state.lowercased() == "running" }
    var isScaledToZero: Bool {
        status.state
            .lowercased()
            .filter(\.isLetter) == "scaledtozero"
    }

    var hardwareDescription: String {
        [compute?.accelerator, compute?.instanceType, compute?.instanceSize]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    var providerDescription: String {
        [provider?.vendor, provider?.region]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

extension JSONDecoder {
    static var hfDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) {
                return date
            }

            let standard = ISO8601DateFormatter()
            standard.formatOptions = [.withInternetDateTime]
            if let date = standard.date(from: value) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO 8601 date: \(value)"
            )
        }
        return decoder
    }
}
