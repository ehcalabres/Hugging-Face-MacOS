//
//  DashboardViewModel.swift
//  Hugging Face
//
//  Created by Enrique Hernández Calabrés on 05/08/2026.
//

import Combine
import Foundation

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var running: [Job] = []
    @Published private(set) var scheduled: [ScheduledJob] = []
    @Published private(set) var endpoints: [InferenceEndpoint] = []
    @Published private(set) var namespace = ""
    @Published private(set) var endpointsNamespace = ""
    @Published private(set) var accountUsername = ""
    @Published private(set) var usageSummary: BillingUsageSnapshot?
    @Published var errorMessage: String?
    @Published var endpointsErrorMessage: String?
    @Published var usageErrorMessage: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var isRefreshingEndpoints = false
    @Published private(set) var isRefreshingUsage = false
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var lastEndpointsUpdated: Date?
    @Published private(set) var lastUsageUpdated: Date?
    @Published private(set) var nextRefreshDate: Date?

    @Published var displayLimit: Int {
        didSet { UserDefaults.standard.set(displayLimit, forKey: Self.displayLimitKey) }
    }
    var pollInterval: TimeInterval {
        didSet { UserDefaults.standard.set(pollInterval, forKey: Self.pollIntervalKey) }
    }
    @Published var automaticRefreshEnabled: Bool {
        didSet {
            UserDefaults.standard.set(automaticRefreshEnabled, forKey: Self.automaticRefreshEnabledKey)
            if !automaticRefreshEnabled {
                nextRefreshDate = nil
            }
        }
    }

    private static let displayLimitKey = "jobsDisplayLimit"
    private static let legacyRecentLimitKey = "recentJobsLimit"
    private static let pollIntervalKey = "jobsPollInterval"
    private static let automaticRefreshEnabledKey = "automaticJobsRefreshEnabled"

    private var pollTask: Task<Void, Never>?
    private let jobsAPI: HuggingFaceJobsAPI
    private let endpointsAPI: HuggingFaceEndpointsAPI
    private let billingAPI: HuggingFaceBillingAPI

    init(jobsAPI: HuggingFaceJobsAPI, endpointsAPI: HuggingFaceEndpointsAPI, billingAPI: HuggingFaceBillingAPI) {
        self.jobsAPI = jobsAPI
        self.endpointsAPI = endpointsAPI
        self.billingAPI = billingAPI

        let savedLimit = UserDefaults.standard.integer(forKey: Self.displayLimitKey)
        let legacyLimit = UserDefaults.standard.integer(forKey: Self.legacyRecentLimitKey)
        displayLimit = savedLimit > 0 ? savedLimit : (legacyLimit > 0 ? legacyLimit : 5)

        let savedInterval = UserDefaults.standard.double(forKey: Self.pollIntervalKey)
        pollInterval = savedInterval > 0 ? savedInterval : 30

        if UserDefaults.standard.object(forKey: Self.automaticRefreshEnabledKey) == nil {
            automaticRefreshEnabled = true
        } else {
            automaticRefreshEnabled = UserDefaults.standard.bool(forKey: Self.automaticRefreshEnabledKey)
        }
    }

    deinit {
        pollTask?.cancel()
    }

    func start() {
        stop()
        guard automaticRefreshEnabled else { return }

        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refreshAll()

                while !Task.isCancelled,
                      self.automaticRefreshEnabled,
                      let nextRefreshDate = self.nextRefreshDate {
                    let remaining = nextRefreshDate.timeIntervalSinceNow
                    guard remaining > 0 else { break }
                    try? await Task.sleep(for: .seconds(remaining))
                }
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        nextRefreshDate = nil
    }

    func refreshAll() async {
        _ = await refresh()
        _ = await refreshEndpoints()
        _ = await refreshUsage()

        if automaticRefreshEnabled {
            nextRefreshDate = Date().addingTimeInterval(pollInterval)
        }
    }

    @discardableResult
    func refresh() async -> Bool {
        guard !isRefreshing else { return errorMessage == nil }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let snapshot = try await jobsAPI.fetchSnapshot()
            let namespaceChanged = namespace != snapshot.namespace
            running = snapshot.active.sorted { $0.createdAt > $1.createdAt }
            scheduled = snapshot.scheduled.sorted {
                if $0.isSuspended != $1.isSuspended {
                    return !$0.isSuspended
                }
                return $0.createdAt > $1.createdAt
            }
            namespace = snapshot.namespace
            if namespaceChanged {
                endpoints = []
                endpointsNamespace = ""
                endpointsErrorMessage = nil
                lastEndpointsUpdated = nil
            }
            lastUpdated = Date()
            errorMessage = nil
            return true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    func cancel(_ job: Job) async {
        do {
            try await jobsAPI.cancelJob(id: job.id, owner: job.owner.name)
            _ = await refresh()
        } catch {
            errorMessage = "Cancel failed: \(error.localizedDescription)"
        }
    }

    func setSuspended(_ suspended: Bool, for job: ScheduledJob) async {
        do {
            try await jobsAPI.setScheduledJobSuspended(
                suspended,
                id: job.id,
                owner: job.owner.name
            )
            _ = await refresh()
        } catch {
            errorMessage = "Could not \(suspended ? "suspend" : "resume") schedule: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func refreshEndpoints() async -> Bool {
        guard !isRefreshingEndpoints else { return endpointsErrorMessage == nil }

        isRefreshingEndpoints = true
        defer { isRefreshingEndpoints = false }

        do {
            let snapshot = try await endpointsAPI.fetchEndpoints()
            endpoints = snapshot.endpoints.sorted {
                if $0.isRunning != $1.isRunning {
                    return $0.isRunning
                }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            endpointsNamespace = snapshot.namespace
            accountUsername = snapshot.username
            lastEndpointsUpdated = Date()
            endpointsErrorMessage = nil
            return true
        } catch {
            endpointsErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    @discardableResult
    func refreshUsage() async -> Bool {
        guard !isRefreshingUsage else { return usageErrorMessage == nil }

        isRefreshingUsage = true
        defer { isRefreshingUsage = false }

        do {
            usageSummary = try await billingAPI.fetchUsage()
            lastUsageUpdated = Date()
            usageErrorMessage = nil
            return true
        } catch {
            usageErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    var billingPageURL: URL {
        URL(string: "https://huggingface.co/settings/billing")!
    }

    func pause(_ endpoint: InferenceEndpoint) async {
        await updateEndpoint(endpoint, action: "pause") {
            try await endpointsAPI.pause(endpoint, namespace: endpointsNamespace)
        }
    }

    func resume(_ endpoint: InferenceEndpoint) async {
        await updateEndpoint(endpoint, action: "resume") {
            try await endpointsAPI.resume(endpoint, namespace: endpointsNamespace)
        }
    }

    func wake(_ endpoint: InferenceEndpoint) async {
        await updateEndpoint(endpoint, action: "wake") {
            try await endpointsAPI.resume(endpoint, namespace: endpointsNamespace)
        }
    }

    func scaleToZero(_ endpoint: InferenceEndpoint) async {
        await updateEndpoint(endpoint, action: "scale to zero") {
            try await endpointsAPI.scaleToZero(endpoint, namespace: endpointsNamespace)
        }
    }

    func logs(jobID: String, owner: String) -> AsyncThrowingStream<String, Error> {
        jobsAPI.streamJobLogs(id: jobID, owner: owner)
    }

    var jobsPageURL: URL {
        let url = URL(string: "https://huggingface.co/settings/jobs")!
        return url
    }

    var endpointsPageURL: URL {
        var url = URL(string: "https://endpoints.huggingface.co")!
        guard !accountUsername.isEmpty else { return url }

        url.append(path: accountUsername)
        url.append(path: "endpoints")
        url.append(path: "dedicated")
        return url
    }

    func endpointConfigurationURL(for endpoint: InferenceEndpoint) -> URL {
        var url = endpointsPageURL
        url.deleteLastPathComponent()
        url.append(path: endpoint.name)
        url.append(path: "settings")
        return url
    }

    var numEndpointsRunning : Int {
        endpoints.filter({$0.isRunning}).count
    }

    var activityCount: Int {
        running.count + scheduled.count + numEndpointsRunning
    }

    private func updateEndpoint(
        _ endpoint: InferenceEndpoint,
        action: String,
        operation: () async throws -> Void
    ) async {
        guard !endpointsNamespace.isEmpty else {
            endpointsErrorMessage = "Refresh Inference Endpoints before changing an endpoint."
            return
        }

        do {
            try await operation()
            _ = await refreshEndpoints()
        } catch {
            endpointsErrorMessage = "Could not \(action) \(endpoint.name): \(error.localizedDescription)"
        }
    }
}
