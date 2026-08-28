import Foundation

struct BillingUsageSnapshot: Sendable {
    let totalUSD: Double
    let jobsUSD: Double
    let endpointsUSD: Double
    let inferenceProvidersUSD: Double
    let otherUSD: Double
    let periodStart: Date
    let periodEnd: Date
}

struct HuggingFaceBillingAPI {
    var baseURL = URL(string: "https://huggingface.co")!
    var tokenProvider: () -> String?

    private struct UsageV2Response: Decodable {
        struct Usage: Decodable {
            let endpoints: [EndpointUsage]?
            let inferenceProviders: InferenceProvidersUsage?
            let jobs: JobsUsage?

            private enum CodingKeys: String, CodingKey {
                case endpoints = "Endpoints"
                case inferenceProviders
                case jobs
            }
        }

        struct EndpointUsage: Decodable {
            let totalCostMicroUSD: Double
        }

        struct InferenceProvidersUsage: Decodable {
            let usedNanoUsd: Double
            let periodStart: Date?
            let periodEnd: Date?
        }

        struct JobsUsage: Decodable {
            let usedMicroUsd: Double
        }

        let usage: Usage
    }

    private struct DateRange: Sendable {
        let start: Date
        let end: Date

        var queryItems: [URLQueryItem] {
            [
                URLQueryItem(name: "startDate", value: String(Int(start.timeIntervalSince1970))),
                URLQueryItem(name: "endDate", value: String(Int(end.timeIntervalSince1970)))
            ]
        }
    }

    private struct ErrorPayload: Decodable {
        let error: String?
        let message: String?
    }

    func fetchUsage() async throws -> BillingUsageSnapshot {
        guard let token = tokenProvider()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else {
            throw HuggingFaceAPIError(message: "Add a Hugging Face token in Settings to load billing usage.")
        }

        let dateRange = currentMonthDateRange()

        do {
            let usageResponse: UsageV2Response = try await fetch(
                UsageV2Response.self,
                path: ["api", "settings", "billing", "usage-v2"],
                queryItems: dateRange.queryItems,
                token: token
            )

            return summary(
                from: usageResponse,
                requestedDateRange: dateRange
            )
        } catch let error as HuggingFaceAPIError {
            throw error
        } catch {
            throw HuggingFaceAPIError(message: "Could not load billing usage: \(error.localizedDescription)")
        }
    }

    private func fetch<Response: Decodable>(
        _ type: Response.Type,
        path: [String],
        queryItems: [URLQueryItem] = [],
        token: String
    ) async throws -> Response {
        var url = baseURL
        for component in path {
            url.append(path: component)
        }

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw HuggingFaceAPIError(message: "Could not build the billing usage URL.")
        }
        components.queryItems = queryItems
        guard let requestURL = components.url else {
            throw HuggingFaceAPIError(message: "Could not build the billing usage URL.")
        }

        var request = URLRequest(url: requestURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("HuggingFaceMacOS/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw HuggingFaceAPIError(message: "Hugging Face returned an invalid billing response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw HuggingFaceAPIError(message: errorMessage(from: data, statusCode: http.statusCode))
        }
        return try JSONDecoder.hfDecoder.decode(Response.self, from: data)
    }

    private func summary(
        from response: UsageV2Response,
        requestedDateRange: DateRange
    ) -> BillingUsageSnapshot {
        let jobs = (response.usage.jobs?.usedMicroUsd ?? 0) / 1_000_000
        let endpoints = (response.usage.endpoints ?? [])
            .reduce(0) { $0 + $1.totalCostMicroUSD } / 1_000_000
        let inferenceProviders = (response.usage.inferenceProviders?.usedNanoUsd ?? 0) / 1_000_000_000
        let other = 0.0

        return BillingUsageSnapshot(
            totalUSD: jobs + endpoints + inferenceProviders + other,
            jobsUSD: jobs,
            endpointsUSD: endpoints,
            inferenceProvidersUSD: inferenceProviders,
            otherUSD: other,
            periodStart: response.usage.inferenceProviders?.periodStart ?? requestedDateRange.start,
            periodEnd: response.usage.inferenceProviders?.periodEnd ?? requestedDateRange.end
        )
    }

    private func currentMonthDateRange(now: Date = .now) -> DateRange {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let components = calendar.dateComponents([.year, .month], from: now)
        let start = calendar.date(from: components)!
        let end = calendar.date(byAdding: .month, value: 1, to: start)!
        return DateRange(start: start, end: end)
    }

    private func errorMessage(from data: Data, statusCode: Int) -> String {
        if let payload = try? JSONDecoder().decode(ErrorPayload.self, from: data),
           let detail = payload.error ?? payload.message,
           !detail.isEmpty {
            return "Billing usage error \(statusCode): \(detail)"
        }
        return "Billing usage returned error \(statusCode)."
    }

}
