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
    private let isTerminal: Bool
    private let dashboardViewModel: DashboardViewModel
    private var task: Task<Void, Never>?
    private var flushTask: Task<Void, Never>?
    private var bufferedOutput = ""

    init(jobID: String, owner: String, isTerminal: Bool, dashboardViewModel: DashboardViewModel) {
        self.jobID = jobID
        self.owner = owner
        self.isTerminal = isTerminal
        self.dashboardViewModel = dashboardViewModel
    }

    func start() {
        guard task == nil else { return }

        state = .streaming
        task = Task { [weak self] in
            guard let self else { return }

            do {
                if isTerminal {
                    let archivedOutput = try await dashboardViewModel.archivedLogs(jobID: jobID, owner: owner)
                    guard !Task.isCancelled else { return }
                    replaceOutput(with: archivedOutput)
                } else {
                    for try await message in dashboardViewModel.logs(jobID: jobID, owner: owner) {
                        guard !Task.isCancelled else { return }
                        append(message)
                    }
                }
                if !Task.isCancelled {
                    flushOutput()
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
        flushTask?.cancel()
        flushTask = nil
    }

    func clear() {
        bufferedOutput = ""
        output = ""
    }

    private func append(_ message: String) {
        if !bufferedOutput.isEmpty && !bufferedOutput.hasSuffix("\n") {
            bufferedOutput.append("\n")
        }
        bufferedOutput.append(message)
        if !message.hasSuffix("\n") {
            bufferedOutput.append("\n")
        }

        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled, let self else { return }
            self.flushOutput()
            self.flushTask = nil
        }
    }

    private func replaceOutput(with text: String) {
        bufferedOutput = text
        flushOutput()
    }

    private func flushOutput() {
        let maximumCharacters = 2_000_000
        if bufferedOutput.count > maximumCharacters {
            bufferedOutput = String(bufferedOutput.suffix(maximumCharacters))
        }
        output = bufferedOutput
    }
}

struct JobLogsView: View {
    @StateObject private var model: JobLogsViewModel

    private let jobID: String
    private let owner: String
    private let jobTitle: String
    private let isTerminal: Bool

    init(
        jobID: String,
        owner: String,
        jobTitle: String,
        isTerminal: Bool,
        dashboardViewModel: DashboardViewModel
    ) {
        self.jobID = jobID
        self.owner = owner
        self.jobTitle = jobTitle
        self.isTerminal = isTerminal
        _model = StateObject(
            wrappedValue: JobLogsViewModel(
                jobID: jobID,
                owner: owner,
                isTerminal: isTerminal,
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

            LogTextView(
                text: model.output.isEmpty ? emptyMessage : model.output,
                isPlaceholder: model.output.isEmpty,
                followsTail: !isTerminal
            )

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
                Text("Logs")
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
        case .streaming: isTerminal ? "Loading saved output" : "Streaming live output"
        case .finished: isTerminal ? "Saved output loaded" : "Stream finished"
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

private struct LogTextView: NSViewRepresentable {
    let text: String
    let isPlaceholder: Bool
    let followsTail: Bool

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .labelColor
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textContainerInset = NSSize(width: 12, height: 10)
        textView.frame = scrollView.contentView.bounds
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        textView.textColor = isPlaceholder ? .secondaryLabelColor : .labelColor
        guard textView.string != text else { return }

        let wasAtTop = scrollView.contentView.bounds.minY <= 1
        textView.string = text
        if followsTail {
            textView.scrollRangeToVisible(NSRange(location: textView.string.utf16.count, length: 0))
        } else if wasAtTop {
            textView.scrollToBeginningOfDocument(nil)
        }
    }
}
