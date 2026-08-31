//
//  HuggingFaceJobsAPI.swift
//  Hugging Face
//
//  Created by Enrique Hernández Calabrés on 05/08/2026.
//

import Foundation

struct HuggingFaceAPIError: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct JobsSnapshot: Sendable {
    let jobs: [Job]
    let scheduled: [ScheduledJob]
    let namespace: String
}

struct HuggingFaceJobsAPI {
    var baseURL: URL
    var tokenProvider: () -> String?
    var namespaceProvider: () -> String?

    private struct UserIdentity: Decodable {
        let name: String
    }

    private struct ErrorPayload: Decodable {
        let error: String?
        let message: String?
    }

    private struct LogEvent: Decodable {
        let data: String
    }

    func fetchSnapshot() async throws -> JobsSnapshot {
        let namespace = namespaceProvider()?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedNamespace: String
        if let namespace, !namespace.isEmpty {
            resolvedNamespace = namespace
        } else {
            resolvedNamespace = try await currentNamespace()
        }

        async let jobs = listJobs(namespace: resolvedNamespace)
        async let scheduled = listScheduledJobs(namespace: resolvedNamespace)

        return try await JobsSnapshot(
            jobs: jobs,
            scheduled: scheduled,
            namespace: resolvedNamespace
        )
    }

    func cancelJob(id: String, owner: String) async throws {
        let request = try makeRequest(
            path: ["api", "jobs", owner, id, "cancel"],
            method: "POST"
        )
        _ = try await send(request)
    }

    func duplicateJob(id: String, owner: String) async throws {
        let request = try makeRequest(
            path: ["api", "jobs", owner, id, "duplicate"],
            method: "POST"
        )
        _ = try await send(request)
    }

    func setScheduledJobSuspended(_ suspended: Bool, id: String, owner: String) async throws {
        let action = suspended ? "suspend" : "resume"
        let request = try makeRequest(
            path: ["api", "scheduled-jobs", owner, id, action],
            method: "POST"
        )
        _ = try await send(request)
    }

    func streamJobLogs(id: String, owner: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = try makeRequest(
                        path: ["api", "jobs", owner, id, "logs"]
                    )
                    request.timeoutInterval = 60 * 60 * 24

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw HuggingFaceAPIError(message: "Hugging Face returned an invalid log stream.")
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        throw HuggingFaceAPIError(message: "Hugging Face returned error \(http.statusCode) for the log stream.")
                    }

                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data: {") else { continue }

                        let payload = String(line.dropFirst("data: ".count))
                        guard let data = payload.data(using: .utf8),
                              let event = try? JSONDecoder().decode(LogEvent.self, from: data),
                              !event.data.hasPrefix("===== Job started") else {
                            continue
                        }
                        continuation.yield(event.data)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func fetchJobLogs(id: String, owner: String) async throws -> String {
        var request = try makeRequest(path: ["api", "jobs", owner, id, "logs"])
        request.timeoutInterval = 60
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        let data = try await send(request)
        guard let response = String(data: data, encoding: .utf8) else {
            throw HuggingFaceAPIError(message: "Hugging Face returned unreadable Job logs.")
        }

        return await Task.detached(priority: .userInitiated) {
            response.components(separatedBy: .newlines).compactMap { line in
                guard !line.isEmpty, line != "event: log", line != ": keep-alive" else { return nil }
                guard line.hasPrefix("data: ") else { return line }

                let payload = String(line.dropFirst("data: ".count))
                guard let eventData = payload.data(using: .utf8),
                      let event = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any],
                      let message = event["data"] as? String,
                      !message.hasPrefix("===== Job started") else {
                    return nil
                }
                return message
            }
            .joined(separator: "\n")
        }.value
    }

    func streamJobMetrics(id: String, owner: String) -> AsyncThrowingStream<JobMetrics, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = try makeRequest(path: ["api", "jobs", owner, id, "metrics"])
                    request.timeoutInterval = 60 * 60
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw HuggingFaceAPIError(message: "Hugging Face returned an invalid metrics stream.")
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        throw HuggingFaceAPIError(message: "Hugging Face returned error \(http.statusCode) for the metrics stream.")
                    }

                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst("data: ".count))
                        guard let data = payload.data(using: .utf8),
                              let metrics = try? JSONDecoder().decode(JobMetrics.self, from: data) else {
                            continue
                        }
                        continuation.yield(metrics)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func currentNamespace() async throws -> String {
        let request = try makeRequest(path: ["api", "whoami-v2"])
        let data = try await send(request)
        return try JSONDecoder().decode(UserIdentity.self, from: data).name
    }

    private func listJobs(namespace: String) async throws -> [Job] {
        var request = try makeRequest(
            path: ["api", "jobs", namespace]
        )
        var jobs: [Job] = []

        while true {
            let (data, response) = try await sendWithResponse(request)
            jobs.append(contentsOf: try JSONDecoder.hfDecoder.decode([Job].self, from: data))

            guard let nextURL = nextPageURL(from: response) else {
                return jobs
            }
            request = try makeRequest(url: nextURL)
        }
    }

    private func listScheduledJobs(namespace: String) async throws -> [ScheduledJob] {
        let request = try makeRequest(path: ["api", "scheduled-jobs", namespace])
        let data = try await send(request)
        return try JSONDecoder.hfDecoder.decode([ScheduledJob].self, from: data)
    }

    private func makeRequest(
        path: [String],
        method: String = "GET",
        query: [URLQueryItem] = []
    ) throws -> URLRequest {
        var url = baseURL
        for component in path {
            url.append(path: component)
        }
        if !query.isEmpty {
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                throw HuggingFaceAPIError(message: "Could not build the Hugging Face Jobs URL.")
            }
            components.queryItems = query
            guard let queryURL = components.url else {
                throw HuggingFaceAPIError(message: "Could not build the Hugging Face Jobs URL.")
            }
            url = queryURL
        }
        return try makeRequest(url: url, method: method)
    }

    private func makeRequest(url: URL, method: String = "GET") throws -> URLRequest {
        guard let token = tokenProvider()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else {
            throw HuggingFaceAPIError(message: "Add a Hugging Face token in Settings to load your Jobs.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("HuggingFaceMacOS/1.0", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, _) = try await sendWithResponse(request)
        return data
    }

    private func sendWithResponse(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
            throw HuggingFaceAPIError(message: "Hugging Face returned an invalid response.")
            }
            guard (200..<300).contains(http.statusCode) else {
                throw HuggingFaceAPIError(message: errorMessage(from: data, statusCode: http.statusCode))
            }
            return (data, http)
        } catch let error as HuggingFaceAPIError {
            throw error
        } catch {
            throw HuggingFaceAPIError(message: "Could not reach Hugging Face: \(error.localizedDescription)")
        }
    }

    private func errorMessage(from data: Data, statusCode: Int) -> String {
        if let payload = try? JSONDecoder().decode(ErrorPayload.self, from: data),
           let detail = payload.error ?? payload.message,
           !detail.isEmpty {
            return "Hugging Face error \(statusCode): \(detail)"
        }
        if let detail = String(data: data, encoding: .utf8), !detail.isEmpty {
            return "Hugging Face error \(statusCode): \(detail)"
        }
        return "Hugging Face returned error \(statusCode)."
    }

    private func nextPageURL(from response: HTTPURLResponse) -> URL? {
        guard let link = response.value(forHTTPHeaderField: "Link") else { return nil }

        for part in link.split(separator: ",") where part.contains("rel=\"next\"") {
            guard let start = part.firstIndex(of: "<"),
                  let end = part[start...].firstIndex(of: ">") else { continue }
            let value = String(part[part.index(after: start)..<end])
            if let url = URL(string: value, relativeTo: baseURL) {
                return url.absoluteURL
            }
        }
        return nil
    }
}
