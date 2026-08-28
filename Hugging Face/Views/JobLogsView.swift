import AppKit
import Combine
import SwiftUI

@MainActor
private final class JobLogsViewModel: ObservableObject {
    enum State {
        case waiting
        case streaming
        case finished
        case failed(String)
    }

    @Published private(set) var output = ""
    @Published private(set) var state: State = .waiting

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

        state = .streaming
        task = Task { [weak self] in
            guard let self else { return }

            do {
                for try await message in dashboardViewModel.logs(jobID: jobID, owner: owner) {
                    guard !Task.isCancelled else { return }
                    append(message)
                }
                if !Task.isCancelled {
                    state = .finished
                }
            } catch {
                if !Task.isCancelled {
                    state = .failed(error.localizedDescription)
                }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    func clear() {
        output = ""
    }

    private func append(_ message: String) {
        if !output.isEmpty && !output.hasSuffix("\n") {
            output.append("\n")
        }
        output.append(message)
        if !message.hasSuffix("\n") {
            output.append("\n")
        }

        let maximumCharacters = 2_000_000
        if output.count > maximumCharacters {
            output.removeFirst(output.count - maximumCharacters)
        }
    }
}

struct JobLogsView: View {
    @StateObject private var model: JobLogsViewModel
    @State private var isFollowingLogs = true

    private let jobID: String
    private let owner: String
    private let jobTitle: String

    init(
        jobID: String,
        owner: String,
        jobTitle: String,
        dashboardViewModel: DashboardViewModel
    ) {
        self.jobID = jobID
        self.owner = owner
        self.jobTitle = jobTitle
        _model = StateObject(
            wrappedValue: JobLogsViewModel(
                jobID: jobID,
                owner: owner,
                dashboardViewModel: dashboardViewModel
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.vertical, 11)

            Divider()

            GeometryReader { viewport in
                ScrollViewReader { proxy in
                    ScrollView([.horizontal, .vertical]) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(model.output.isEmpty ? emptyMessage : model.output)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(model.output.isEmpty ? .secondary : .primary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: true, vertical: true)

                            Spacer(minLength: 0)

                            Color.clear
                                .frame(height: 1)
                                .id("bottom")
                        }
                        .frame(
                            minWidth: max(0, viewport.size.width - 24),
                            minHeight: max(0, viewport.size.height - 24),
                            alignment: .topLeading
                        )
                        .padding(12)
                    }
                    .background(Color(nsColor: .textBackgroundColor))
                    .onScrollGeometryChange(for: Bool.self, of: { geometry in
                        geometry.contentOffset.y + geometry.containerSize.height
                            >= geometry.contentSize.height - 2
                    }, action: { _, isAtBottom in
                        isFollowingLogs = isAtBottom
                    })
                    .onChange(of: model.output) {
                        guard isFollowingLogs else { return }
                        proxy.scrollTo("bottom", anchor: .bottomLeading)
                    }
                }
            }

            Divider()

            footer
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
        }
        .frame(minWidth: 520, minHeight: 300)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    private var header: some View {
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
        }
    }

    private var footer: some View {
        HStack {
            Text(jobID)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Spacer()

            Button("Clear") {
                model.clear()
            }
            .controlSize(.small)
            .disabled(model.output.isEmpty)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(model.output, forType: .string)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .controlSize(.small)
            .disabled(model.output.isEmpty)
        }
    }

    private var emptyMessage: String {
        switch model.state {
        case .waiting, .streaming:
            "Waiting for log output…"
        case .finished:
            "The job finished without producing log output."
        case .failed(let message):
            message
        }
    }

    private var stateText: String {
        switch model.state {
        case .waiting: "Connecting…"
        case .streaming: "Streaming live output"
        case .finished: "Stream finished"
        case .failed: "Stream failed"
        }
    }

    private var stateColor: Color {
        switch model.state {
        case .waiting: .orange
        case .streaming: .green
        case .finished: .secondary
        case .failed: .red
        }
    }

    private var jobURL: URL {
        URL(string: "https://huggingface.co")!
            .appending(path: "jobs")
            .appending(path: owner)
            .appending(path: jobID)
    }
}
