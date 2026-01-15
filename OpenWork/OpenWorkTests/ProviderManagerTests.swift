import XCTest
@testable import OpenWork

@MainActor
final class ProviderManagerTests: XCTestCase {

    var providerManager: ProviderManager!

    override func setUp() async throws {
        providerManager = ProviderManager()
    }

    override func tearDown() async throws {
        // Clean up any added providers
        for provider in providerManager.providers {
            providerManager.removeProvider(id: provider.id)
        }
        providerManager = nil
    }

    // MARK: - Initialization

    func testInitialState() {
        // Should have at least one provider (Ollama default)
        XCTAssertFalse(providerManager.providers.isEmpty)
        XCTAssertNotNil(providerManager.activeProviderID)
    }

    // MARK: - Provider CRUD

    func testAddProvider() {
        let initialCount = providerManager.providers.count

        let config = LLMProviderConfig(
            name: "Test Provider",
            baseURL: "http://localhost:8080",
            apiKey: "test-key",
            model: "test-model",
            customHeaders: [:],
            isEnabled: true
        )

        providerManager.addProvider(config)

        XCTAssertEqual(providerManager.providers.count, initialCount + 1)
        XCTAssertTrue(providerManager.providers.contains { $0.id == config.id })
    }

    func testUpdateProvider() {
        let config = LLMProviderConfig(
            name: "Original Name",
            baseURL: "http://localhost:8080",
            apiKey: "",
            model: "model",
            customHeaders: [:],
            isEnabled: true
        )

        providerManager.addProvider(config)

        var updated = config
        updated.name = "Updated Name"
        updated.model = "new-model"

        providerManager.updateProvider(updated)

        let found = providerManager.providers.first { $0.id == config.id }
        XCTAssertEqual(found?.name, "Updated Name")
        XCTAssertEqual(found?.model, "new-model")
    }

    func testRemoveProvider() {
        let config = LLMProviderConfig(
            name: "To Remove",
            baseURL: "http://localhost:8080",
            apiKey: "",
            model: "model",
            customHeaders: [:],
            isEnabled: true
        )

        providerManager.addProvider(config)
        XCTAssertTrue(providerManager.providers.contains { $0.id == config.id })

        providerManager.removeProvider(id: config.id)
        XCTAssertFalse(providerManager.providers.contains { $0.id == config.id })
    }

    // MARK: - Active Provider

    func testSetActiveProvider() {
        let config = LLMProviderConfig(
            name: "New Active",
            baseURL: "http://localhost:8080",
            apiKey: "",
            model: "model",
            customHeaders: [:],
            isEnabled: true
        )

        providerManager.addProvider(config)
        providerManager.setActiveProvider(id: config.id)

        XCTAssertEqual(providerManager.activeProviderID, config.id)
        XCTAssertEqual(providerManager.activeProvider?.id, config.id)
    }

    func testActiveProviderAfterRemoval() {
        let config1 = LLMProviderConfig(
            name: "Provider 1",
            baseURL: "http://localhost:8080",
            apiKey: "",
            model: "model",
            customHeaders: [:],
            isEnabled: true
        )
        let config2 = LLMProviderConfig(
            name: "Provider 2",
            baseURL: "http://localhost:8081",
            apiKey: "",
            model: "model",
            customHeaders: [:],
            isEnabled: true
        )

        providerManager.addProvider(config1)
        providerManager.addProvider(config2)
        providerManager.setActiveProvider(id: config1.id)

        providerManager.removeProvider(id: config1.id)

        // Should auto-select another provider
        XCTAssertNotNil(providerManager.activeProviderID)
        XCTAssertNotEqual(providerManager.activeProviderID, config1.id)
    }

    // MARK: - Presets

    func testAddPreset() {
        let initialCount = providerManager.providers.count

        providerManager.addPreset(.openAI)

        XCTAssertEqual(providerManager.providers.count, initialCount + 1)
        XCTAssertTrue(providerManager.providers.contains { $0.name == "OpenAI" })
    }

    func testAllPresets() {
        // Verify all presets can be created
        for preset in LLMProviderConfig.Preset.allCases {
            let config = preset.defaultConfig
            XCTAssertFalse(config.name.isEmpty)
            // Custom preset has empty baseURL by design
            if preset != .custom {
                XCTAssertFalse(config.baseURL.isEmpty, "Preset \(preset) should have a baseURL")
            }
        }
    }
}

// MARK: - LLMProviderConfig Tests

final class LLMProviderConfigTests: XCTestCase {

    func testValidConfiguration() {
        let config = LLMProviderConfig(
            name: "Test",
            baseURL: "http://localhost:8080",
            apiKey: "",
            model: "gpt-4",
            customHeaders: [:],
            isEnabled: true
        )

        XCTAssertTrue(config.isValid)
    }

    func testInvalidConfigurationEmptyURL() {
        let config = LLMProviderConfig(
            name: "Test",
            baseURL: "",
            apiKey: "",
            model: "gpt-4",
            customHeaders: [:],
            isEnabled: true
        )

        XCTAssertFalse(config.isValid)
    }

    func testInvalidConfigurationEmptyModel() {
        let config = LLMProviderConfig(
            name: "Test",
            baseURL: "http://localhost:8080",
            apiKey: "",
            model: "",
            customHeaders: [:],
            isEnabled: true
        )

        XCTAssertFalse(config.isValid)
    }

    // MARK: - Chat Completions URL

    func testOpenAICompatibleURL() {
        let config = LLMProviderConfig(
            name: "Test",
            baseURL: "https://api.openai.com/v1",
            apiKey: "",
            model: "gpt-4",
            customHeaders: [:],
            isEnabled: true,
            apiFormat: .openAICompatible
        )

        XCTAssertEqual(config.chatCompletionsURL?.absoluteString, "https://api.openai.com/v1/chat/completions")
    }

    func testOllamaNativeURL() {
        let config = LLMProviderConfig(
            name: "Ollama",
            baseURL: "http://localhost:11434",
            apiKey: "",
            model: "llama3.2",
            customHeaders: [:],
            isEnabled: true,
            apiFormat: .ollamaNative
        )

        XCTAssertEqual(config.chatCompletionsURL?.absoluteString, "http://localhost:11434/api/chat")
    }

    func testAnthropicURL() {
        let config = LLMProviderConfig(
            name: "Anthropic",
            baseURL: "https://api.anthropic.com/v1",
            apiKey: "",
            model: "claude-sonnet-4-20250514",
            customHeaders: [:],
            isEnabled: true,
            apiFormat: .anthropic
        )

        XCTAssertEqual(config.chatCompletionsURL?.absoluteString, "https://api.anthropic.com/v1/messages")
    }

    func testGeminiURL() {
        let config = LLMProviderConfig(
            name: "Gemini",
            baseURL: "https://generativelanguage.googleapis.com/v1beta",
            apiKey: "",
            model: "gemini-1.5-pro",
            customHeaders: [:],
            isEnabled: true,
            apiFormat: .gemini
        )

        let url = config.chatCompletionsURL?.absoluteString
        XCTAssertTrue(url?.contains("gemini-1.5-pro:generateContent") == true)
    }

    // MARK: - Preset Configurations

    func testOllamaPreset() {
        let config = LLMProviderConfig.Preset.ollama.defaultConfig

        XCTAssertEqual(config.name, "Ollama")
        XCTAssertEqual(config.baseURL, "http://localhost:11434")
        XCTAssertEqual(config.apiFormat, .ollamaNative)
        XCTAssertTrue(config.isEnabled)
    }

    func testOpenAIPreset() {
        let config = LLMProviderConfig.Preset.openAI.defaultConfig

        XCTAssertEqual(config.name, "OpenAI")
        XCTAssertEqual(config.baseURL, "https://api.openai.com/v1")
        XCTAssertEqual(config.apiFormat, .openAICompatible)
        XCTAssertEqual(config.model, "gpt-4o")
    }

    func testAnthropicPreset() {
        let config = LLMProviderConfig.Preset.anthropic.defaultConfig

        XCTAssertEqual(config.name, "Anthropic")
        XCTAssertEqual(config.apiFormat, .anthropic)
        XCTAssertTrue(config.customHeaders.keys.contains("anthropic-version"))
    }

    func testGeminiPreset() {
        let config = LLMProviderConfig.Preset.gemini.defaultConfig

        XCTAssertEqual(config.name, "Google Gemini")
        XCTAssertEqual(config.apiFormat, .gemini)
    }
}

// MARK: - APIFormat Tests

final class APIFormatTests: XCTestCase {

    func testDisplayNames() {
        XCTAssertEqual(APIFormat.openAICompatible.displayName, "OpenAI Compatible")
        XCTAssertEqual(APIFormat.ollamaNative.displayName, "Ollama Native")
        XCTAssertEqual(APIFormat.anthropic.displayName, "Anthropic Messages")
        XCTAssertEqual(APIFormat.gemini.displayName, "Google Gemini")
    }

    func testRawValues() {
        XCTAssertEqual(APIFormat.openAICompatible.rawValue, "openai")
        XCTAssertEqual(APIFormat.ollamaNative.rawValue, "ollama")
        XCTAssertEqual(APIFormat.anthropic.rawValue, "anthropic")
        XCTAssertEqual(APIFormat.gemini.rawValue, "gemini")
    }
}

// MARK: - ProviderError Tests

final class ProviderErrorTests: XCTestCase {

    func testErrorDescriptions() {
        XCTAssertEqual(ProviderError.invalidURL.errorDescription, "Invalid provider URL")
        XCTAssertEqual(ProviderError.invalidResponse.errorDescription, "Invalid response from provider")
        XCTAssertEqual(ProviderError.noActiveProvider.errorDescription, "No active provider configured")

        let httpError = ProviderError.httpError(statusCode: 401, message: "Unauthorized")
        XCTAssertTrue(httpError.errorDescription?.contains("401") == true)

        let connError = ProviderError.connectionError("timeout")
        XCTAssertEqual(connError.errorDescription, "timeout")
    }
}
