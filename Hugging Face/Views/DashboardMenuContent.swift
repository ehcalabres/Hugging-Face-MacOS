//
//  DashboardMenuContent.swift
//  Hugging Face
//
//  Created by Enrique Hernández Calabrés on 05/08/2026.
//

import AppKit
import SwiftUI

struct DashboardMenuContent: View {
    @EnvironmentObject private var vm: DashboardViewModel
    @State private var selectedTab: DashboardTab = .jobs
    @State private var showsAllJobs = false

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(14)

            UsageSummaryCard()
                .environmentObject(vm)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)

            DashboardSwitch(selection: $selectedTab)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)

            Divider()

            dashboardContent

            Divider()

            footer
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
    }

    private var header: some View {
        HStack(spacing: 11) {
            HuggingFaceHeaderIconView()
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(selectedTab == .jobs ? "Hugging Face Jobs" : "Hugging Face Inference Endpoints")
                    .font(.headline)

                Text(activitySummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task { await vm.refreshAll() }
            } label: {
                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 16, height: 16)
                }
            }
            .buttonStyle(.borderless)
            .help("Refresh Jobs, Endpoints, and usage")
            .keyboardShortcut("r", modifiers: .command)
            .disabled(isRefreshing)

            Button {
                NSWorkspace.shared.open(selectedTab == .jobs ? vm.jobsPageURL : vm.endpointsPageURL)
            } label: {
                Image(systemName: "plus")
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.borderless)
            .help(selectedTab == .jobs ? "Create a Job on Hugging Face" : "Deploy Endpoint on Hugging Face")
            .keyboardShortcut("n", modifiers: .command)

        }
    }

    private var activitySummary: String {
        guard selectedTab == .jobs else {
            return vm.endpoints.count == 1 ? "1 endpoint" : "\(vm.endpoints.count) endpoints"
        }
        let active = vm.jobs.count == 1 ? "1 job" : "\(vm.jobs.count) jobs"
        let schedules = vm.scheduled.count == 1 ? "1 schedule" : "\(vm.scheduled.count) schedules"
        return "\(active) · \(schedules)"
    }

    @ViewBuilder
    private var dashboardContent: some View {
        if selectedTab == .jobs {
            jobsContent
        } else {
            endpointsContent
        }
    }

    private var jobsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let error = vm.errorMessage {
                    ErrorBanner(message: error) {
                        vm.errorMessage = nil
                    }
                }

                activeJobsSection

                Divider()

                scheduledJobsSection
            }
            .padding(14)
            .background(CompactScrollViewConfigurator())
        }
        .frame(minHeight: 260, maxHeight: 560)
    }

    private var endpointsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let error = vm.endpointsErrorMessage {
                    ErrorBanner(message: error) {
                        vm.endpointsErrorMessage = nil
                    }
                }

                JobSection(title: "Endpoints", count: vm.endpoints.count) {
                    if vm.endpoints.isEmpty {
                        EmptyJobsView(
                            title: "No Inference Endpoints",
                            message: "Deployed endpoints in this namespace will appear here."
                        )
                    } else {
                        LazyVStack(spacing: 7) {
                            ForEach(vm.endpoints.prefix(vm.displayLimit)) { endpoint in
                                EndpointRow(endpoint: endpoint)
                            }
                        }

                        if vm.endpoints.count > vm.displayLimit {
                            ShowMoreButton(
                                hiddenCount: vm.endpoints.count - vm.displayLimit,
                                destination: vm.endpointsPageURL
                            )
                        }
                    }
                }
            }
            .padding(14)
            .background(CompactScrollViewConfigurator())
        }
        .frame(minHeight: 260, maxHeight: 560)
        .task(id: selectedTab) {
            guard selectedTab == .endpoints, vm.lastEndpointsUpdated == nil else { return }
            await vm.refreshEndpoints()
        }
    }

    private var isRefreshing: Bool {
        vm.isRefreshing || vm.isRefreshingEndpoints || vm.isRefreshingUsage
    }

    private var activeJobsSection: some View {
        JobSection(title: "Jobs", count: vm.filteredJobs.count) {
            jobFilters

            if vm.filteredJobs.isEmpty {
                EmptyJobsView(
                    title: "No matching jobs",
                    message: "Try a different state or time period."
                )
            } else {
                LazyVStack(spacing: 7) {
                    ForEach(vm.filteredJobs.prefix(showsAllJobs ? vm.filteredJobs.count : vm.displayLimit)) { job in
                        JobRow(job: job)
                    }
                }

                if vm.filteredJobs.count > vm.displayLimit {
                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            showsAllJobs.toggle()
                        }
                    } label: {
                        HStack {
                            Text(showsAllJobs ? "Show fewer" : "Show \(vm.filteredJobs.count - vm.displayLimit) more")
                            Spacer()
                            Image(systemName: showsAllJobs ? "chevron.up" : "chevron.down")
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private var jobFilters: some View {
        HStack(spacing: 8) {
            Picker("State", selection: $vm.jobStateFilter) {
                ForEach(JobStateFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .labelsHidden()

            Picker("Period", selection: $vm.jobPeriodFilter) {
                ForEach(JobPeriodFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .labelsHidden()

            Spacer()

            if vm.jobStateFilter != .all || vm.jobPeriodFilter != .all {
                Button("Clear") {
                    vm.jobStateFilter = .all
                    vm.jobPeriodFilter = .all
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .controlSize(.small)
    }

    private var scheduledJobsSection: some View {
        JobSection(title: "Scheduled Jobs", count: vm.scheduled.count) {
            if vm.scheduled.isEmpty {
                EmptyJobsView(
                    title: "No scheduled jobs",
                    message: "Active and suspended schedules will appear here."
                )
            } else {
                LazyVStack(spacing: 7) {
                    ForEach(vm.scheduled.prefix(vm.displayLimit)) { job in
                        ScheduledJobRow(job: job)
                    }
                }

                if vm.scheduled.count > vm.displayLimit {
                    ShowMoreButton(
                        hiddenCount: vm.scheduled.count - vm.displayLimit,
                        destination: vm.jobsPageURL
                    )
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let nextRefreshDate = vm.nextRefreshDate {
                Label {
                    Text(nextRefreshDate, style: .relative)
                } icon: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .help("Next automatic refresh")
            } else if !vm.automaticRefreshEnabled {
                Label("Manual refresh", systemImage: "hand.tap")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Preparing refresh…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                NSWorkspace.shared.open(
                    selectedTab == .jobs ? vm.jobsPageURL : vm.endpointsPageURL
                )
            } label: {
                Image(systemName: "arrow.up.right.square")
            }
            .buttonStyle(.borderless)
            .help(selectedTab == .jobs ? "Open Hugging Face Jobs" : "Open Inference Endpoints")
            .keyboardShortcut("o", modifiers: .command)

            Button {
                SettingsWindowController.shared.show(viewModel: vm)
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")
            .keyboardShortcut(",", modifiers: .command)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help("Quit Hugging Face")
            .keyboardShortcut("q", modifiers: .command)
        }
    }

}

private struct CompactScrollViewConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let marker = NSView(frame: .zero)
        Self.configureScroller(from: marker)
        return marker
    }

    func updateNSView(_ marker: NSView, context: Context) {
        Self.configureScroller(from: marker)
    }

    private static func configureScroller(from marker: NSView) {
        DispatchQueue.main.async { [weak marker] in
            var ancestor = marker?.superview

            while let view = ancestor {
                if let scrollView = view as? NSScrollView {
                    scrollView.verticalScroller?.controlSize = .small
                    scrollView.horizontalScroller?.controlSize = .small
                    scrollView.tile()
                    return
                }

                ancestor = view.superview
            }
        }
    }
}

private enum DashboardTab: String, CaseIterable, Identifiable {
    case jobs
    case endpoints

    var id: Self { self }

    var title: String {
        switch self {
        case .jobs: "Jobs"
        case .endpoints: "Endpoints"
        }
    }

    var symbolName: String {
        switch self {
        case .jobs: "briefcase"
        case .endpoints: "point.3.connected.trianglepath.dotted"
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .jobs: "1"
        case .endpoints: "2"
        }
    }
}

private struct UsageSummaryCard: View {
    @EnvironmentObject private var vm: DashboardViewModel
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("USAGE THIS PERIOD")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.7)

                    Spacer()

                    if let summary = vm.usageSummary {
                        Text(summary.totalUSD, format: .currency(code: "USD"))
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Collapse usage" : "Expand usage")

            if isExpanded, let summary = vm.usageSummary {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(summary.totalUSD, format: .currency(code: "USD"))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()

                    Text("total usage")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(periodText(for: summary))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 0) {
                    UsageMetric(title: "Jobs", amount: summary.jobsUSD)
                    UsageMetric(title: "Endpoints", amount: summary.endpointsUSD)
                    UsageMetric(title: "Inference Providers", amount: summary.inferenceProvidersUSD)
                }

                if summary.otherUSD > 0 {
                    Text("Includes \(summary.otherUSD.formatted(.currency(code: "USD"))) in other Hugging Face usage.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else if isExpanded, vm.isRefreshingUsage {
                Text("Loading billing usage…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if isExpanded, let error = vm.usageErrorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else if isExpanded {
                Text("Billing usage will appear after the first refresh.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if isExpanded {
                Button {
                    NSWorkspace.shared.open(vm.billingPageURL)
                } label: {
                    Label("Open billing settings", systemImage: "arrow.up.right")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.05))
        }
    }

    private func periodText(for summary: BillingUsageSnapshot) -> String {
        "\(summary.periodStart.formatted(date: .abbreviated, time: .omitted)) – \(summary.periodEnd.formatted(date: .abbreviated, time: .omitted))"
    }
}

private struct UsageMetric: View {
    let title: String
    let amount: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(amount, format: .currency(code: "USD"))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DashboardSwitch: View {
    @Binding var selection: DashboardTab

    var body: some View {
        HStack(spacing: 2) {
            ForEach(DashboardTab.allCases) { tab in
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        selection = tab
                    }
                } label: {
                    Label(tab.title, systemImage: tab.symbolName)
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .foregroundStyle(selection == tab ? .primary : .secondary)
                        .background {
                            if selection == tab {
                                Capsule()
                                    .fill(Color.primary.opacity(0.1))
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(tab.shortcut, modifiers: .command)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.045), in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.primary.opacity(0.055))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Dashboard")
    }
}

private struct JobSection<Content: View>: View {
    let title: String
    let count: Int
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.7)

                Spacer()

                if count > 0 {
                    Text("\(count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }

            content()
        }
    }
}

private struct ShowMoreButton: View {
    let hiddenCount: Int
    let destination: URL

    var body: some View {
        Button {
            NSWorkspace.shared.open(destination)
        } label: {
            HStack {
                Text("Show \(hiddenCount) more")
                Spacer()
                Image(systemName: "arrow.up.right")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
        .help("Open all Jobs on Hugging Face")
    }
}

private struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .padding(.top, 1)

            Text(message)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 4)

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Dismiss")
        }
        .padding(10)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(Color.orange.opacity(0.2))
        }
    }
}

private struct EmptyJobsView: View {
    let title: String
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.title3)
                .foregroundStyle(.tertiary)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(11)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct ExpandableCard<Content: View>: View {
    let isExpanded: Bool
    let toggle: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var isHovering = false

    var body: some View {
        content()
            .padding(10)
            .background(
                Color.primary.opacity(isHovering ? 0.055 : 0.035),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(isHovering ? 0.11 : 0.055))
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.14), value: isHovering)
            .gesture(
                TapGesture().onEnded { _ in toggle() },
                including: .gesture
            )
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(isExpanded ? "Click to hide details" : "Click to show details")
            .accessibilityAction(named: isExpanded ? "Hide details" : "Show details") {
                toggle()
            }
    }
}

private struct JobRow: View {
    @EnvironmentObject private var vm: DashboardViewModel
    @AppStorage(HuggingFacePreferences.compactDashboardKey) private var compactDashboard = false
    @State private var showsDetails = false

    let job: Job

    var body: some View {
        ExpandableCard(
            isExpanded: showsDetails,
            toggle: {
                withAnimation(.easeInOut(duration: 0.16)) { showsDetails.toggle() }
            }
        ) {
            if compactDashboard {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        StatusIcon(status: job.status)
                        Text(job.displayName)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        jobActions
                    }

                    if showsDetails {
                        Divider().padding(.vertical, 9)
                        JobDetails(job: job)
                    }
                }
            } else {
            VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                StatusIcon(status: job.status)

                VStack(alignment: .leading, spacing: 5) {
                    Text(job.displayName)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)

                    Text(job.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    HStack(spacing: 7) {
                        StatusBadge(status: job.status)

                        Text(job.flavor)
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Text("·")
                            .foregroundStyle(.tertiary)

                        Text(job.createdAt, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 2)

                jobActions
            }

            if showsDetails {
                Divider()
                    .padding(.vertical, 9)

                JobDetails(job: job)
            }
            }
            }
        }
        .help(job.statusMessage ?? job.id)
    }

    private var jobActions: some View {
        HStack(spacing: 2) {
            if job.status.isActive {
                RowActionButton(
                    systemName: "stop.circle",
                    help: "Cancel Job",
                    tint: .red
                ) {
                    Task { await vm.cancel(job) }
                }
            }

            RowActionButton(
                systemName: "terminal",
                help: job.status.isActive ? "Job Metrics and Logs" : "View Saved Logs"
            ) {
                JobLogsWindowController.shared.show(
                    jobID: job.id,
                    owner: job.owner.name,
                    title: job.displayName,
                    isTerminal: !job.status.isActive,
                    viewModel: vm
                )
            }
        }
    }
}

private struct ScheduledJobRow: View {
    @EnvironmentObject private var vm: DashboardViewModel
    @AppStorage(HuggingFacePreferences.compactDashboardKey) private var compactDashboard = false
    @State private var showsDetails = false

    let job: ScheduledJob

    private var activeRun: Job? {
        guard let lastJobID = job.status.lastJob?.id else { return nil }
        return vm.running.first { $0.id == lastJobID }
    }

    var body: some View {
        ExpandableCard(
            isExpanded: showsDetails,
            toggle: {
                withAnimation(.easeInOut(duration: 0.16)) { showsDetails.toggle() }
            }
        ) {
            if compactDashboard {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        ScheduleStatusIcon(isSuspended: job.isSuspended, isRunning: activeRun != nil)
                        Text(job.displayName)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        scheduleActions
                    }

                    if showsDetails {
                        Divider().padding(.vertical, 9)
                        ScheduledJobDetails(job: job, jobsPageURL: vm.jobsPageURL)
                    }
                }
            } else {
            VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                ScheduleStatusIcon(isSuspended: job.isSuspended, isRunning: activeRun != nil)

                VStack(alignment: .leading, spacing: 5) {
                    Text(job.displayName)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)

                    Text(job.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    HStack(spacing: 7) {
                        ScheduleStatusBadge(
                            isSuspended: job.isSuspended,
                            isRunning: activeRun != nil
                        )

                        Text(job.schedule ?? "Schedule unavailable")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 2)

                scheduleActions
            }

            if showsDetails {
                Divider()
                    .padding(.vertical, 9)

                ScheduledJobDetails(job: job, jobsPageURL: vm.jobsPageURL)
            }
            }
            }
        }
    }

    private var scheduleActions: some View {
        HStack(spacing: 2) {
            if let activeRun {
                RowActionButton(
                    systemName: "stop.circle",
                    help: "Cancel Current Run",
                    tint: .red
                ) {
                    Task { await vm.cancel(activeRun) }
                }
            }

            RowActionButton(
                systemName: job.isSuspended ? "play.circle" : "pause.circle",
                help: job.isSuspended ? "Resume Schedule" : "Suspend Schedule"
            ) {
                Task { await vm.setSuspended(!job.isSuspended, for: job) }
            }

            RowActionButton(
                systemName: "terminal",
                help: job.status.lastJob == nil ? "No runs yet" : "View Latest Run Logs",
                isDisabled: job.status.lastJob == nil
            ) {
                guard let lastJob = job.status.lastJob else { return }
                JobLogsWindowController.shared.show(
                    jobID: lastJob.id,
                    owner: job.owner.name,
                    title: job.displayName,
                    isTerminal: !(vm.jobs.first { $0.id == lastJob.id }?.status.isActive ?? false),
                    viewModel: vm
                )
            }
        }
    }
}

private struct EndpointRow: View {
    @EnvironmentObject private var vm: DashboardViewModel
    @AppStorage(HuggingFacePreferences.compactDashboardKey) private var compactDashboard = false
    @State private var showsDetails = false

    let endpoint: InferenceEndpoint

    var body: some View {
        ExpandableCard(
            isExpanded: showsDetails,
            toggle: {
                withAnimation(.easeInOut(duration: 0.16)) { showsDetails.toggle() }
            }
        ) {
            if compactDashboard {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        EndpointStatusIcon(status: endpoint.status)
                        Text(endpoint.name)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        endpointActions
                    }

                    if showsDetails {
                        Divider().padding(.vertical, 9)
                        EndpointDetails(
                            endpoint: endpoint,
                            namespace: vm.endpointsNamespace,
                            configurationURL: vm.endpointConfigurationURL(for: endpoint)
                        )
                    }
                }
            } else {
            VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                EndpointStatusIcon(status: endpoint.status)

                VStack(alignment: .leading, spacing: 5) {
                    Text(endpoint.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)

                    Text(endpoint.model.repository)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    HStack(spacing: 7) {
                        EndpointStatusBadge(status: endpoint.status)

                        if !endpoint.hardwareDescription.isEmpty {
                            Text(endpoint.hardwareDescription)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer(minLength: 2)

                endpointActions
            }

            if showsDetails {
                Divider()
                    .padding(.vertical, 9)

                EndpointDetails(
                    endpoint: endpoint,
                    namespace: vm.endpointsNamespace,
                    configurationURL: vm.endpointConfigurationURL(for: endpoint)
                )
            }
            }
            }
        }
        .help(endpoint.status.message ?? endpoint.name)
    }

    private var endpointActions: some View {
        HStack(spacing: 2) {
            endpointLifecycleAction

            if endpoint.isRunning {
                RowActionButton(
                    systemName: "arrow.down.to.line.compact",
                    help: "Scale to Zero"
                ) {
                    Task { await vm.scaleToZero(endpoint) }
                }
            }

            RowActionButton(
                systemName: "doc.on.doc",
                help: endpoint.status.url == nil ? "Endpoint URL unavailable" : "Copy Endpoint URL",
                isDisabled: endpoint.status.url == nil
            ) {
                guard let url = endpoint.status.url else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
            }
        }
    }

    @ViewBuilder
    private var endpointLifecycleAction: some View {
        if endpoint.isPaused {
            RowActionButton(systemName: "play.circle", help: "Resume Endpoint") {
                Task { await vm.resume(endpoint) }
            }
        } else if endpoint.isScaledToZero {
            RowActionButton(systemName: "bolt.circle", help: "Wake Endpoint") {
                Task { await vm.wake(endpoint) }
            }
        } else if endpoint.isRunning {
            RowActionButton(systemName: "pause.circle", help: "Pause Endpoint") {
                Task { await vm.pause(endpoint) }
            }
        }
    }
}

private struct RowActionButton: View {
    let systemName: String
    let help: String
    var tint: Color = .secondary
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isDisabled ? tint.opacity(0.35) : tint)
        .disabled(isDisabled)
        .help(help)
    }
}

private struct JobDetails: View {
    let job: Job

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DetailLine(label: "Job ID", value: job.id)
            DetailLine(label: "Namespace", value: job.owner.name)
            DetailLine(label: "Created", value: job.createdAt.detailText)
            if let startedAt = job.startedAt {
                DetailLine(label: "Started", value: startedAt.detailText)
            }
            if let finishedAt = job.finishedAt {
                DetailLine(label: "Finished", value: finishedAt.detailText)
            }
            DetailLine(label: "Command", value: job.detail)

            if let url = job.webURL {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("Open full details on Hugging Face", systemImage: "arrow.up.right")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                .padding(.top, 2)
            }
        }
    }
}

private struct ScheduledJobDetails: View {
    let job: ScheduledJob
    let jobsPageURL: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DetailLine(label: "Schedule ID", value: job.id)
            DetailLine(label: "Namespace", value: job.owner.name)
            DetailLine(label: "Schedule", value: job.schedule ?? "Unavailable")
            DetailLine(label: "Hardware", value: job.jobSpec.flavor ?? "Default")
            DetailLine(label: "Created", value: job.createdAt.detailText)
            DetailLine(label: "Next run", value: job.status.nextJobRunAt?.detailText ?? "Suspended")
            if let lastRun = job.status.lastJob {
                DetailLine(label: "Last run", value: lastRun.at.detailText)
            }
            DetailLine(label: "Command", value: job.detail)

            Button {
                NSWorkspace.shared.open(jobsPageURL)
            } label: {
                Label("Open scheduled jobs on Hugging Face", systemImage: "arrow.up.right")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
            .padding(.top, 2)
        }
    }
}

private struct EndpointDetails: View {
    let endpoint: InferenceEndpoint
    let namespace: String
    let configurationURL: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DetailLine(label: "Namespace", value: namespace)
            DetailLine(label: "Model", value: endpoint.model.repository)
            DetailLine(label: "State", value: endpoint.status.displayName)
            DetailLine(label: "Framework", value: endpoint.model.framework ?? "Default")
            DetailLine(
                label: "Hardware",
                value: endpoint.hardwareDescription.isEmpty ? "Default" : endpoint.hardwareDescription
            )
            DetailLine(
                label: "Provider",
                value: endpoint.providerDescription.isEmpty ? "Default" : endpoint.providerDescription
            )

            if let scaling = endpoint.compute?.scaling {
                let replicas = "\(scaling.minReplica ?? 0)–\(scaling.maxReplica ?? 0) replicas"
                DetailLine(label: "Scaling", value: replicas)
            }
            if let task = endpoint.model.task {
                DetailLine(label: "Task", value: task)
            }
            if let updatedAt = endpoint.status.updatedAt {
                DetailLine(label: "Updated", value: updatedAt.detailText)
            }
            if let url = endpoint.status.url {
                DetailLine(label: "URL", value: url.absoluteString)
            }

            Button {
                NSWorkspace.shared.open(configurationURL)
            } label: {
                Label("Open Endpoint settings on Hugging Face", systemImage: "arrow.up.right")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
            .padding(.top, 2)
        }
    }
}

private struct DetailLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)

            Text(value)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .font(.caption2)
    }
}

private struct StatusIcon: View {
    let status: Job.Status

    var body: some View {
        Image(systemName: status.symbolName)
            .font(.caption.weight(.bold))
            .foregroundStyle(status.color)
            .frame(width: 25, height: 25)
            .background(status.color.opacity(0.12), in: Circle())
            .accessibilityHidden(true)
    }
}

private struct EndpointStatusIcon: View {
    let status: InferenceEndpoint.Status

    var body: some View {
        Image(systemName: status.symbolName)
            .font(.caption.weight(.bold))
            .foregroundStyle(status.color)
            .frame(width: 25, height: 25)
            .background(status.color.opacity(0.12), in: Circle())
            .accessibilityHidden(true)
    }
}

private struct ScheduleStatusIcon: View {
    let isSuspended: Bool
    let isRunning: Bool

    var body: some View {
        let color: Color = isRunning ? .blue : (isSuspended ? .secondary : .green)
        let symbol = isRunning ? "play.fill" : (isSuspended ? "pause.fill" : "calendar.badge.clock")

        Image(systemName: symbol)
            .font(.caption.weight(.bold))
            .foregroundStyle(color)
            .frame(width: 25, height: 25)
            .background(color.opacity(0.12), in: Circle())
            .accessibilityHidden(true)
    }
}

private struct StatusBadge: View {
    let status: Job.Status

    var body: some View {
        Text(status.displayName)
            .font(.caption2.weight(.medium))
            .foregroundStyle(status.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(status.color.opacity(0.1), in: Capsule())
    }
}

private struct EndpointStatusBadge: View {
    let status: InferenceEndpoint.Status

    var body: some View {
        Text(status.displayName)
            .font(.caption2.weight(.medium))
            .foregroundStyle(status.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(status.color.opacity(0.1), in: Capsule())
    }
}

private struct ScheduleStatusBadge: View {
    let isSuspended: Bool
    let isRunning: Bool

    var body: some View {
        let title = isRunning ? "Running" : (isSuspended ? "Suspended" : "Active")
        let color: Color = isRunning ? .blue : (isSuspended ? .secondary : .green)

        Text(title)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.1), in: Capsule())
    }
}

private extension Job.Status {
    var color: Color {
        switch self {
        case .scheduling: .orange
        case .running: .blue
        case .completed: .green
        case .error: .red
        case .canceled, .deleted: .secondary
        }
    }

    var symbolName: String {
        switch self {
        case .scheduling: "clock.fill"
        case .running: "play.fill"
        case .completed: "checkmark"
        case .error: "xmark"
        case .canceled: "minus"
        case .deleted: "trash.fill"
        }
    }
}

private extension InferenceEndpoint.Status {
    var displayName: String {
        switch state.lowercased() {
        case "pending": "Pending"
        case "initializing": "Initializing"
        case "running": "Running"
        case "paused": "Paused"
        case "scalingtozero", "scaledtozero": "Scaled to zero"
        case "failed", "updatefailed": "Failed"
        default: state.capitalized
        }
    }

    var color: Color {
        switch state.lowercased() {
        case "running": .green
        case "paused", "scalingtozero", "scaledtozero": .secondary
        case "failed", "updatefailed": .red
        case "pending", "initializing": .orange
        default: .blue
        }
    }

    var symbolName: String {
        switch state.lowercased() {
        case "running": "bolt.fill"
        case "paused": "pause.fill"
        case "scalingtozero", "scaledtozero": "arrow.down.to.line.compact"
        case "failed", "updatefailed": "xmark"
        case "pending", "initializing": "clock.fill"
        default: "circle.fill"
        }
    }
}

private extension Date {
    var detailText: String {
        formatted(date: .abbreviated, time: .standard)
    }
}
