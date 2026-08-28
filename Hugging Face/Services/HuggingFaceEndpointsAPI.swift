import Foundation

struct EndpointsSnapshot: Sendable {
    let endpoints: [InferenceEndpoint]
    let namespace: String
    let username: String
}

struct HuggingFaceEndpointsAPI {
    var baseURL = URL(string: "https://api.endpoints.huggingface.cloud/v2")!
    var hubBaseURL = URL(string: "https://huggingface.co")!
    var tokenProvider: () -> String?
    var namespaceProvider: () -> String?

    private struct EndpointList: Decodable {
        let items: [InferenceEndpoint]
    }

    private struct UserIdentity: Decodable {
        let name: String
    }

    private struct ErrorPayload: Decodable {
        let error: String?
        let message: String?
    }

    func fetchEndpoints() async throws -> EndpointsSnapshot {
        let username = try await authenticatedUsername()
        let namespace = resolvedNamespace(username: username)
        let request = try makeRequest(path: ["endpoint", namespace])
        let data = try await send(request)
        let endpoints = try JSONDecoder.hfDecoder.decode(EndpointList.self, from: data).items
        return EndpointsSnapshot(endpoints: endpoints, namespace: namespace, username: username)
    }

    func pause(_ endpoint: InferenceEndpoint, namespace: String) async throws {
        let request = try makeRequest(
            path: ["endpoint", namespace, endpoint.name, "pause"],
            method: "POST"
        )
        _ = try await send(request)
    }

    func resume(_ endpoint: InferenceEndpoint, namespace: String) async throws {
        let request = try makeRequest(
            path: ["endpoint", namespace, endpoint.name, "resume"],
            method: "POST"
        )
        _ = try await send(request)
    }

    func scaleToZero(_ endpoint: InferenceEndpoint, namespace: String) async throws {
        let request = try makeRequest(
            path: ["endpoint", namespace, endpoint.name, "scale-to-zero"],
            method: "POST"
        )
        _ = try await send(request)
    }

    private func resolvedNamespace(username: String) -> String {
        if let namespace = namespaceProvider()?.trimmingCharacters(in: .whitespacesAndNewlines),
           !namespace.isEmpty {
            return namespace
        }

        return username
    }

    private func authenticatedUsername() async throws -> String {
        let request = try makeRequest(
            url: hubBaseURL
                .appending(path: "api")
                .appending(path: "whoami-v2")
        )
        let data = try await send(request)
        return try JSONDecoder().decode(UserIdentity.self, from: data).name
    }

    private func makeRequest(path: [String], method: String = "GET") throws -> URLRequest {
        var url = baseURL
        for component in path {
            url.append(path: component)
        }
        return try makeRequest(url: url, method: method)
    }

    private func makeRequest(url: URL, method: String = "GET") throws -> URLRequest {
        guard let token = tokenProvider()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else {
            throw HuggingFaceAPIError(message: "Add a Hugging Face token in Settings to load your Inference Endpoints.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("HuggingFaceMacOS/1.0", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw HuggingFaceAPIError(message: "Hugging Face returned an invalid Inference Endpoints response.")
            }
            guard (200..<300).contains(http.statusCode) else {
                throw HuggingFaceAPIError(message: errorMessage(from: data, statusCode: http.statusCode))
            }
            return data
        } catch let error as HuggingFaceAPIError {
            throw error
        } catch {
            throw HuggingFaceAPIError(message: "Could not reach Hugging Face Inference Endpoints: \(error.localizedDescription)")
        }
    }

    private func errorMessage(from data: Data, statusCode: Int) -> String {
        if let payload = try? JSONDecoder().decode(ErrorPayload.self, from: data),
           let detail = payload.error ?? payload.message,
           !detail.isEmpty {
            return "Inference Endpoints error \(statusCode): \(detail)"
        }
        if let detail = String(data: data, encoding: .utf8), !detail.isEmpty {
            return "Inference Endpoints error \(statusCode): \(detail)"
        }
        return "Inference Endpoints returned error \(statusCode)."
    }
}
