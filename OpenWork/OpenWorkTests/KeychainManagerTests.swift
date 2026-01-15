import XCTest
@testable import OpenWork

final class KeychainManagerTests: XCTestCase {

    let testKey = "OpenWork.Test.Key"
    let testProviderID = UUID()

    override func tearDown() {
        // Clean up test data
        KeychainManager.shared.delete(key: testKey)
        try? KeychainManager.shared.deleteAPIKey(for: testProviderID)
    }

    // MARK: - Generic Data Storage

    func testSaveAndLoadData() {
        let testData = "Hello, Keychain!".data(using: .utf8)!

        KeychainManager.shared.save(key: testKey, data: testData)
        let loaded = KeychainManager.shared.load(key: testKey)

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded, testData)
    }

    func testLoadNonExistentKey() {
        let loaded = KeychainManager.shared.load(key: "NonExistent.Key.12345")

        XCTAssertNil(loaded)
    }

    func testDeleteData() {
        let testData = "To Delete".data(using: .utf8)!

        KeychainManager.shared.save(key: testKey, data: testData)
        XCTAssertNotNil(KeychainManager.shared.load(key: testKey))

        KeychainManager.shared.delete(key: testKey)
        XCTAssertNil(KeychainManager.shared.load(key: testKey))
    }

    func testOverwriteData() {
        let data1 = "First Value".data(using: .utf8)!
        let data2 = "Second Value".data(using: .utf8)!

        KeychainManager.shared.save(key: testKey, data: data1)
        KeychainManager.shared.save(key: testKey, data: data2)

        let loaded = KeychainManager.shared.load(key: testKey)
        XCTAssertEqual(loaded, data2)
    }

    // MARK: - API Key Storage

    func testSaveAndGetAPIKey() throws {
        let apiKey = "sk-test-api-key-12345"

        try KeychainManager.shared.saveAPIKey(apiKey, for: testProviderID)
        let retrieved = KeychainManager.shared.getAPIKey(for: testProviderID)

        XCTAssertEqual(retrieved, apiKey)
    }

    func testGetNonExistentAPIKey() {
        let fakeID = UUID()
        let key = KeychainManager.shared.getAPIKey(for: fakeID)

        XCTAssertNil(key)
    }

    func testDeleteAPIKey() throws {
        let apiKey = "sk-to-delete"

        try KeychainManager.shared.saveAPIKey(apiKey, for: testProviderID)
        XCTAssertNotNil(KeychainManager.shared.getAPIKey(for: testProviderID))

        try KeychainManager.shared.deleteAPIKey(for: testProviderID)
        XCTAssertNil(KeychainManager.shared.getAPIKey(for: testProviderID))
    }

    func testUpdateAPIKey() throws {
        let oldKey = "old-api-key"
        let newKey = "new-api-key"

        try KeychainManager.shared.saveAPIKey(oldKey, for: testProviderID)
        try KeychainManager.shared.updateAPIKey(newKey, for: testProviderID)

        let retrieved = KeychainManager.shared.getAPIKey(for: testProviderID)
        XCTAssertEqual(retrieved, newKey)
    }

    func testSaveEmptyAPIKey() throws {
        // First save a real key
        try KeychainManager.shared.saveAPIKey("real-key", for: testProviderID)

        // Save empty key should effectively delete
        try KeychainManager.shared.saveAPIKey("", for: testProviderID)

        // Empty keys are not stored
        let retrieved = KeychainManager.shared.getAPIKey(for: testProviderID)
        XCTAssertNil(retrieved)
    }

    // MARK: - JSON Data Storage (for Connectors)

    func testStoreAndRetrieveCredentials() {
        struct TestCredentials: Codable, Equatable {
            let accessToken: String
            let refreshToken: String
            let expiresAt: Date
        }

        let credentials = TestCredentials(
            accessToken: "access-123",
            refreshToken: "refresh-456",
            expiresAt: Date()
        )

        let data = try! JSONEncoder().encode(credentials)
        KeychainManager.shared.save(key: testKey, data: data)

        let loadedData = KeychainManager.shared.load(key: testKey)!
        let decoded = try! JSONDecoder().decode(TestCredentials.self, from: loadedData)

        XCTAssertEqual(decoded.accessToken, credentials.accessToken)
        XCTAssertEqual(decoded.refreshToken, credentials.refreshToken)
    }

    // MARK: - Edge Cases

    func testLargeData() {
        // Create 10KB of data
        let largeData = Data(repeating: 0xAB, count: 10 * 1024)

        KeychainManager.shared.save(key: testKey, data: largeData)
        let loaded = KeychainManager.shared.load(key: testKey)

        XCTAssertEqual(loaded?.count, largeData.count)
        XCTAssertEqual(loaded, largeData)
    }

    func testSpecialCharactersInKey() {
        let specialKey = "OpenWork.Test.Key!@#$%^&*()"
        let data = "test".data(using: .utf8)!

        KeychainManager.shared.save(key: specialKey, data: data)
        let loaded = KeychainManager.shared.load(key: specialKey)

        XCTAssertEqual(loaded, data)

        // Cleanup
        KeychainManager.shared.delete(key: specialKey)
    }

    func testUnicodeData() {
        let unicodeString = "Hello 世界 🌍 مرحبا"
        let data = unicodeString.data(using: .utf8)!

        KeychainManager.shared.save(key: testKey, data: data)
        let loaded = KeychainManager.shared.load(key: testKey)

        XCTAssertNotNil(loaded)
        XCTAssertEqual(String(data: loaded!, encoding: .utf8), unicodeString)
    }
}

// MARK: - KeychainError Tests

final class KeychainErrorTests: XCTestCase {

    func testErrorDescriptions() {
        XCTAssertEqual(
            KeychainError.encodingFailed.errorDescription,
            "Failed to encode data for Keychain"
        )

        XCTAssertTrue(
            KeychainError.saveFailed(-25299).errorDescription?.contains("-25299") == true
        )

        XCTAssertTrue(
            KeychainError.deleteFailed(-25300).errorDescription?.contains("-25300") == true
        )

        XCTAssertEqual(
            KeychainError.notFound.errorDescription,
            "Item not found in Keychain"
        )
    }
}
