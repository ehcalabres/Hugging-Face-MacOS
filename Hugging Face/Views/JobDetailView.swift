import AppKit
import Charts
import Combine
import SwiftUI

@MainActor
private final class JobMetricsViewModel: ObservableObject {
    enum State: Equatable {
        case connecting
        case streaming
        case finished
        case failed(String)
    }

    struct Sample: Identifiable {
        let id = UUID()
        let date: Date
        let cpu: Double
        let memory: Double
    }

    @Published private(set) var metrics: JobMetrics?
    @Published private(set) var samples: [Sample] = []
    @Published private(set) var state: State = .connecting

    private let jobID: String
    private let owner: String
    private let dashboardViewModel: DashboardViewModel
    private var task: Task<Void, Never>?

    init(jobID: String, owner: String, dashboardViewModel: DashboardViewModel) {
        self.jobID = jobID
        self.owner = owner
        self.dashboardViewModel = dashboardViewModel
    }

    func start() {
        guard task == nil else { return }
        state = .connecting
        task = Task { [weak self] in
            guard let self else { return }
            do {
                for try await metrics in dashboardViewModel.metrics(jobID: jobID, owner: owner) {
                    guard !Task.isCancelled else { return }
                    self.metrics = metrics
                    self.state = .streaming
                    self.samples.append(
                        Sample(
                            date: Date(),
                            cpu: metrics.cpuUsagePercent,
                            memory: metrics.memoryUsagePercent
                        )
                    )
                    if self.samples.count > 120 {
                        self.samples.removeFirst(self.samples.count - 120)
                    }
                }
                if !Task.isCancelled { state = .finished }
            } catch {
                if !Task.isCancelled { state = .failed(error.localizedDescription) }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}

struct JobDetailView: View {
    let jobID: String
    let owner: String
    let jobTitle: String
    let isTerminal: Bool
    let dashboardViewModel: DashboardViewModel

    var body: some View {
        VStack(spacing: 0) {
            JobMetricsView(
                jobID: jobID,
                owner: owner,
                jobTitle: jobTitle,
                isTerminal: isTerminal,
                dashboardViewModel: dashboardViewModel
            )
            .frame(minHeight: 280, idealHeight: 360, maxHeight: 430)

            Divider()

            JobLogsView(
                jobID: jobID,
                owner: owner,
                jobTitle: jobTitle,
                isTerminal: isTerminal,
                dashboardViewModel: dashboardViewModel
            )
            .frame(minHeight: 280)
        }
    }
}

private struct JobMetricsView: View {
    @StateObject private var model: JobMetricsViewModel

    private let jobTitle: String
    private let isTerminal: Bool
    private let jobURL: URL

    init(
        jobID: String,
        owner: String,
        jobTitle: String,
        isTerminal: Bool,
        dashboardViewModel: DashboardViewModel
    ) {
        self.jobTitle = jobTitle
        self.isTerminal = isTerminal
        jobURL = URL(string: "https://huggingface.co")!
            .appending(path: "jobs")
            .appending(path: owner)
            .appending(path: jobID)
        _model = StateObject(
            wrappedValue: JobMetricsViewModel(
                jobID: jobID,
                owner: owner,
                dashboardViewModel: dashboardViewModel
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Circle()
                    .fill(stateColor)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 1) {
                    Text(jobTitle)
                        .font(.headline)
                        .lineLimit(1)
                    Text(stateText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    NSWorkspace.shared.open(jobURL)
                } label: {
                    Label("Open Job", systemImage: "arrow.up.right.square")
                }
                .controlSize(.small)
                .keyboardShortcut("o", modifiers: .command)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            Divider()

            ScrollView {
                if isTerminal {
                    ContentUnavailableView {
                        Label("Metrics unavailable", systemImage: "chart.xyaxis.line")
                    } description: {
                        Text("Metrics are only available while a job is running. This job has finished, been canceled, or terminated.")
                    }
                    .frame(maxWidth: .infinity, minHeight: 300)
                } else if let metrics = model.metrics {
                    metricsContent(metrics)
                        .padding(16)
                } else {
                    ContentUnavailableView {
                        Label("Waiting for metrics", systemImage: "waveform.path.ecg")
                    } description: {
                        Text(emptyMessage)
                    }
                    .frame(maxWidth: .infinity, minHeight: 300)
                }
            }
        }
        .onAppear {
            if !isTerminal {
                model.start()
            }
        }
        .onDisappear { model.stop() }
    }

    private func metricsContent(_ metrics: JobMetrics) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                MetricCard(
                    title: "CPU",
                    value: metrics.cpuUsagePercent.formatted(.number.precision(.fractionLength(1))) + "%",
                    detail: (Double(metrics.cpuMillicores) / 1000).formatted(.number.precision(.fractionLength(2))) + " cores",
                    tint: .orange
                )
                MetricCard(
                    title: "Memory",
                    value: metrics.memoryUsagePercent.formatted(.number.precision(.fractionLength(1))) + "%",
                    detail: "\(formatBytes(metrics.memoryUsedBytes)) / \(formatBytes(metrics.memoryTotalBytes))",
                    tint: .blue
                )
                MetricCard(
                    title: "Network",
                    value: "↓ \(formatRate(metrics.receivedBytesPerSecond))",
                    detail: "↑ \(formatRate(metrics.transmittedBytesPerSecond))",
                    tint: .purple
                )
            }

            if model.samples.count > 1 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("LIVE UTILIZATION")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.7)

                    Chart {
                        ForEach(model.samples) { sample in
                            LineMark(
                                x: .value("Time", sample.date),
                                y: .value("CPU", sample.cpu)
                            )
                            .foregroundStyle(by: .value("Resource", "CPU"))

                            LineMark(
                                x: .value("Time", sample.date),
                                y: .value("Memory", sample.memory)
                            )
                            .foregroundStyle(by: .value("Resource", "Memory"))
                        }
                    }
                    .chartYScale(domain: 0...100)
                    .frame(height: 180)
                }
            }

            if !metrics.gpus.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("GPU")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.7)

                    ForEach(metrics.gpus) { gpu in
                        GPUCard(gpu: gpu)
                    }
                }
            }

            Text("Replica \(metrics.replica)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
    }

    private var stateText: String {
        if isTerminal { return "Metrics unavailable" }

        return switch model.state {
        case .connecting: "Connecting to metrics…"
        case .streaming: "Live metrics"
        case .finished: "Metrics stream finished"
        case .failed: "Metrics unavailable"
        }
    }

    private var stateColor: Color {
        if isTerminal { return .secondary }

        return switch model.state {
        case .connecting: .orange
        case .streaming: .green
        case .finished: .secondary
        case .failed: .red
        }
    }

    private var emptyMessage: String {
        switch model.state {
        case .connecting: "Metrics will appear when Hugging Face reports the first sample."
        case .streaming: "Waiting for the next sample."
        case .finished: "No metrics were recorded for this job."
        case .failed(let message): message
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory)
    }

    private func formatRate(_ bytes: Int64) -> String {
        "\(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .decimal))/s"
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let detail: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).stroke(tint.opacity(0.16)) }
    }
}

private struct GPUCard: View {
    let gpu: JobMetrics.GPU

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(gpu.name)
                    .font(.subheadline.weight(.medium))
                Spacer()
                if let temperature = gpu.temperature {
                    Text(temperature.formatted(.number.precision(.fractionLength(1))) + " °C")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if let utilization = gpu.utilization {
                LabeledMetricProgress(title: "Utilization", value: utilization)
            }
            if let utilization = gpu.memoryUtilization {
                LabeledMetricProgress(title: "Memory", value: utilization)
            }
            if let used = gpu.memoryUsedBytes, let total = gpu.memoryTotalBytes {
                Text("\(ByteCountFormatter.string(fromByteCount: used, countStyle: .memory)) / \(ByteCountFormatter.string(fromByteCount: total, countStyle: .memory))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct LabeledMetricProgress: View {
    let title: String
    let value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(value.formatted(.number.precision(.fractionLength(1))) + "%")
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            ProgressView(value: min(max(value, 0), 100), total: 100)
        }
    }
}
