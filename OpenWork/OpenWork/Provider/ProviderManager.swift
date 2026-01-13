import Foundation
import SwiftUI

/// Manages LLM provider configurations and the active provider
@MainActor
class ProviderManager: ObservableObject {
    @Published var providers: [LLMProviderConfig] = []
    @Published var activeProviderID: UUID?
    @Published var isConnecting: Bool = false
    @Published var connectionError: String?

    private let userDefaults = UserDefaults.standard
    private let providersKey = "openwork.providers"
    private let activeProviderKey = "openwork.activeProvider"

    var activeProvider: LLMProviderConfig? {
        guard let id = activeProviderID else { return nil }
        return providers.first { $0.id == id }
    }

    init() {
        loadProviders()

        // If no providers, add Ollama as default
        if providers.isEmpty {
            let ollama = LLMProviderConfig.Preset.ollama.defaultConfig
            providers.append(ollama)
            activeProviderID = ollama.id
            saveProviders()
        }
    }

    // MARK: - Persistence

    private func loadProviders() {
        if let data = userDefaults.data(forKey: providersKey),
           let decoded = try? JSONDecoder().decode([LLMProviderConfig].self, from: data) {
            providers = decoded
        }

        if let idString = userDefaults.string(forKey: activeProviderKey),
           let id = UUID(uuidString: idString) {
            activeProviderID = id
        }
    }

    func saveProviders() {
        if let encoded = try? JSONEncoder().encode(providers) {
            userDefaults.set(encoded, forKey: providersKey)
        }

        if let id = activeProviderID {
            userDefaults.set(id.uuidString, forKey: activeProviderKey)
        }
    }

    // MARK: - Provider Management

    func addProvider(_ config: LLMProviderConfig) {
        providers.append(config)
        if activeProviderID == nil {
            activeProviderID = config.id
        }
        saveProviders()
    }

    func updateProvider(_ config: LLMProviderConfig) {
        if let index = providers.firstIndex(where: { $0.id == config.id }) {
            providers[index] = config
            saveProviders()
        }
    }

    func removeProvider(id: UUID) {
        providers.removeAll { $0.id == id }
        if activeProviderID == id {
            activeProviderID = providers.first?.id
        }
        saveProviders()
    }

    func setActiveProvider(id: UUID) {
        activeProviderID = id
        saveProviders()
    }

    func addPreset(_ preset: LLMProviderConfig.Preset) {
        var config = preset.defaultConfig
        config.id = UUID()
        addProvider(config)
    }

    // MARK: - Connection Testing

    func testConnection(for provider: LLMProviderConfig) async -> Result<String, Error> {
        guard let url = provider.chatCompletionsURL else {
            return .failure(ProviderError.invalidURL)
        }

        print("[OpenWork] Testing connection to: \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        // Add API key if present
        if !provider.apiKey.isEmpty {
            request.setValue("Bearer \(provider.apiKey)", forHTTPHeaderField: "Authorization")
        }

        // Add custom headers
        for (key, value) in provider.customHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // Simple test message - format depends on API type
        var body: [String: Any]

        if provider.apiFormat == .ollamaNative {
            // Ollama native format
            body = [
                "model": provider.model,
                "messages": [
                    ["role": "user", "content": "Hi"]
                ],
                "stream": false
            ]
        } else {
            // OpenAI-compatible format
            body = [
                "model": provider.model,
                "messages": [
                    ["role": "user", "content": "Hi"]
                ],
                "max_tokens": 5,
                "stream": false
            ]
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            print("[OpenWork] Request body: \(String(data: request.httpBody!, encoding: .utf8) ?? "")")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(ProviderError.invalidResponse)
            }

            print("[OpenWork] Response status: \(httpResponse.statusCode)")
            let responseBody = String(data: data, encoding: .utf8) ?? ""
            print("[OpenWork] Response: \(responseBody.prefix(500))")

            if httpResponse.statusCode == 200 {
                return .success("Connection successful!")
            } else {
                return .failure(ProviderError.httpError(statusCode: httpResponse.statusCode, message: responseBody))
            }
        } catch let error as NSError {
            print("[OpenWork] Connection error: \(error.localizedDescription)")
            print("[OpenWork] Error domain: \(error.domain), code: \(error.code)")

            // Provide more helpful error messages
            if error.domain == NSURLErrorDomain {
                switch error.code {
                case NSURLErrorNotConnectedToInternet:
                    return .failure(ProviderError.connectionError("No internet connection"))
                case NSURLErrorTimedOut:
                    return .failure(ProviderError.connectionError("Connection timed out"))
                case NSURLErrorCannotFindHost:
                    return .failure(ProviderError.connectionError("Cannot find host: \(url.host ?? "unknown")"))
                case NSURLErrorCannotConnectToHost:
                    return .failure(ProviderError.connectionError("Cannot connect to host: \(url.host ?? "unknown")"))
                case NSURLErrorSecureConnectionFailed:
                    return .failure(ProviderError.connectionError("SSL/TLS connection failed"))
                default:
                    return .failure(ProviderError.connectionError(error.localizedDescription))
                }
            }
            return .failure(error)
        }
    }
}

enum ProviderError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, message: String)
    case noActiveProvider
    case connectionError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid provider URL"
        case .invalidResponse:
            return "Invalid response from provider"
        case .httpError(let code, let message):
            return "HTTP \(code): \(message)"
        case .noActiveProvider:
            return "No active provider configured"
        case .connectionError(let msg):
            return msg
        }
    }
}
