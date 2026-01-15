import XCTest
@testable import OpenWork

@MainActor
final class SkillRegistryTests: XCTestCase {

    var skillRegistry: SkillRegistry!

    override func setUp() async throws {
        skillRegistry = SkillRegistry.shared
        // Deactivate all skills for clean state
        for (id, _) in skillRegistry.activeSkills {
            skillRegistry.deactivate(id: id)
        }
    }

    override func tearDown() async throws {
        // Deactivate all skills
        for (id, _) in skillRegistry.activeSkills {
            skillRegistry.deactivate(id: id)
        }
    }

    // MARK: - Available Skills

    func testAvailableSkillsNotEmpty() {
        XCTAssertFalse(skillRegistry.availableSkills.isEmpty)
    }

    func testDocumentSkillExists() {
        let documentSkill = skillRegistry.availableSkills.first { $0.id == "document" }
        XCTAssertNotNil(documentSkill)
    }

    // MARK: - Skill Activation

    func testActivateSkill() {
        let skillId = "document"

        skillRegistry.activate(id: skillId)

        XCTAssertNotNil(skillRegistry.activeSkills[skillId])
        XCTAssertTrue(skillRegistry.isActive(skillId))
    }

    func testDeactivateSkill() {
        let skillId = "document"

        skillRegistry.activate(id: skillId)
        XCTAssertTrue(skillRegistry.isActive(skillId))

        skillRegistry.deactivate(id: skillId)
        XCTAssertFalse(skillRegistry.isActive(skillId))
    }

    func testActivateNonExistentSkill() {
        skillRegistry.activate(id: "non-existent-skill")

        // Should not crash, just do nothing
        XCTAssertFalse(skillRegistry.isActive("non-existent-skill"))
    }

    func testDoubleActivation() {
        let skillId = "document"

        skillRegistry.activate(id: skillId)
        skillRegistry.activate(id: skillId)

        // Should only be active once (dictionary key is unique)
        XCTAssertNotNil(skillRegistry.activeSkills[skillId])
    }

    // MARK: - System Prompt

    func testCombinedSystemPromptEmpty() {
        // With no active skills
        let prompt = skillRegistry.combinedSystemPrompt()

        // May be empty or contain base content
        XCTAssertNotNil(prompt)
    }

    func testCombinedSystemPromptWithActiveSkill() {
        skillRegistry.activate(id: "document")

        let prompt = skillRegistry.combinedSystemPrompt()

        // Should contain document skill's system prompt addition
        XCTAssertFalse(prompt.isEmpty)
    }

    // MARK: - Tool Registry Integration

    func testSetToolRegistry() {
        let toolRegistry = ToolRegistry.shared

        // Should not crash
        skillRegistry.setToolRegistry(toolRegistry)
    }

    // MARK: - Skills by Category

    func testSkillsByCategory() {
        let categories = SkillCategory.allCases

        for category in categories {
            let skills = skillRegistry.skills(in: category)
            // Just verify the method works
            XCTAssertNotNil(skills)
        }
    }

    // MARK: - Skill Query

    func testSkillForID() {
        let skill = skillRegistry.skill(forID: "document")
        XCTAssertNotNil(skill)
        XCTAssertEqual(skill?.id, "document")
    }

    func testSkillForIDNotFound() {
        let skill = skillRegistry.skill(forID: "nonexistent")
        XCTAssertNil(skill)
    }

    // MARK: - Toggle

    func testToggleSkill() {
        let skillId = "document"

        XCTAssertFalse(skillRegistry.isActive(skillId))

        skillRegistry.toggle(id: skillId)
        XCTAssertTrue(skillRegistry.isActive(skillId))

        skillRegistry.toggle(id: skillId)
        XCTAssertFalse(skillRegistry.isActive(skillId))
    }
}

// MARK: - Skill Protocol Tests

final class SkillProtocolTests: XCTestCase {

    func testDocumentSkillProperties() {
        let skill = DocumentSkill()

        XCTAssertEqual(skill.id, "document")
        XCTAssertFalse(skill.name.isEmpty)
        XCTAssertFalse(skill.description.isEmpty)
        XCTAssertFalse(skill.icon.isEmpty)
        XCTAssertEqual(skill.category, .productivity)
        XCTAssertFalse(skill.systemPromptAddition.isEmpty)
    }

    func testDocumentSkillTools() {
        let skill = DocumentSkill()
        let tools = skill.tools

        XCTAssertFalse(tools.isEmpty)
    }

    func testDocumentSkillDefaults() {
        let skill = DocumentSkill()

        // Check default implementations
        // Note: DocumentSkill is enabled by default
        XCTAssertTrue(skill.enabledByDefault)
        XCTAssertTrue(skill.requiredConfiguration.isEmpty)
    }

    func testCodeReviewSkillProperties() {
        let skill = CodeReviewSkill()

        XCTAssertEqual(skill.id, "code-review")
        XCTAssertEqual(skill.category, .development)
        XCTAssertFalse(skill.systemPromptAddition.isEmpty)
    }

    func testResearchSkillProperties() {
        let skill = ResearchSkill()

        XCTAssertEqual(skill.id, "research")
        XCTAssertEqual(skill.category, .research)
        XCTAssertFalse(skill.systemPromptAddition.isEmpty)
    }
}

// MARK: - SkillCategory Tests

final class SkillCategoryTests: XCTestCase {

    func testAllCases() {
        let allCases = SkillCategory.allCases

        XCTAssertTrue(allCases.contains(.productivity))
        XCTAssertTrue(allCases.contains(.development))
        XCTAssertTrue(allCases.contains(.research))
        XCTAssertTrue(allCases.contains(.communication))
        XCTAssertTrue(allCases.contains(.creative))
        XCTAssertTrue(allCases.contains(.data))
        XCTAssertTrue(allCases.contains(.system))
    }

    func testRawValues() {
        XCTAssertEqual(SkillCategory.productivity.rawValue, "Productivity")
        XCTAssertEqual(SkillCategory.development.rawValue, "Development")
        XCTAssertEqual(SkillCategory.research.rawValue, "Research")
        XCTAssertEqual(SkillCategory.communication.rawValue, "Communication")
        XCTAssertEqual(SkillCategory.creative.rawValue, "Creative")
        XCTAssertEqual(SkillCategory.data.rawValue, "Data")
        XCTAssertEqual(SkillCategory.system.rawValue, "System")
    }

    func testIcons() {
        for category in SkillCategory.allCases {
            XCTAssertFalse(category.icon.isEmpty, "Category \(category) should have an icon")
        }
    }

    func testCodable() throws {
        let category = SkillCategory.productivity
        let encoded = try JSONEncoder().encode(category)
        let decoded = try JSONDecoder().decode(SkillCategory.self, from: encoded)

        XCTAssertEqual(decoded, category)
    }
}

// MARK: - SkillConfiguration Tests

final class SkillConfigurationTests: XCTestCase {

    func testDefaultConfiguration() {
        let config = SkillConfiguration(skillId: "test")

        XCTAssertEqual(config.skillId, "test")
        XCTAssertFalse(config.isEnabled)
        XCTAssertTrue(config.settings.isEmpty)
    }

    func testConfigurationWithSettings() {
        let config = SkillConfiguration(
            skillId: "test",
            isEnabled: true,
            settings: ["key1": "value1", "key2": "value2"]
        )

        XCTAssertTrue(config.isEnabled)
        XCTAssertEqual(config.settings["key1"], "value1")
        XCTAssertEqual(config.settings["key2"], "value2")
    }

    func testCodable() throws {
        let config = SkillConfiguration(
            skillId: "test-skill",
            isEnabled: true,
            settings: ["apiKey": "secret"]
        )

        let encoded = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(SkillConfiguration.self, from: encoded)

        XCTAssertEqual(decoded.skillId, config.skillId)
        XCTAssertEqual(decoded.isEnabled, config.isEnabled)
        XCTAssertEqual(decoded.settings, config.settings)
    }
}

// MARK: - SkillConfigOption Tests

final class SkillConfigOptionTests: XCTestCase {

    func testTextConfigOption() {
        let option = SkillConfigOption(
            id: "api-key",
            name: "API Key",
            description: "Your API key",
            type: .text,
            required: true
        )

        XCTAssertEqual(option.id, "api-key")
        XCTAssertTrue(option.required)
    }

    func testPasswordConfigOption() {
        let option = SkillConfigOption(
            id: "secret",
            name: "Secret",
            description: "Secret value",
            type: .password,
            required: true
        )

        if case .password = option.type {
            // Correct type
        } else {
            XCTFail("Expected password type")
        }
    }

    func testSelectionConfigOption() {
        let option = SkillConfigOption(
            id: "model",
            name: "Model",
            description: "Select a model",
            type: .selection(["gpt-4", "gpt-3.5", "claude"]),
            required: true
        )

        if case .selection(let options) = option.type {
            XCTAssertEqual(options.count, 3)
            XCTAssertTrue(options.contains("gpt-4"))
        } else {
            XCTFail("Expected selection type")
        }
    }

    func testBooleanConfigOption() {
        let option = SkillConfigOption(
            id: "enabled",
            name: "Enabled",
            description: "Enable feature",
            type: .boolean,
            required: false,
            defaultValue: "true"
        )

        XCTAssertEqual(option.defaultValue, "true")
        XCTAssertFalse(option.required)
    }
}

// MARK: - ActiveSkill Tests

final class ActiveSkillTests: XCTestCase {

    func testActiveSkillCreation() {
        let skill = DocumentSkill()
        let config = SkillConfiguration(skillId: skill.id, isEnabled: true)
        let activeSkill = ActiveSkill(
            skill: skill,
            activatedAt: Date(),
            configuration: config
        )

        XCTAssertEqual(activeSkill.skill.id, "document")
        XCTAssertTrue(activeSkill.configuration.isEnabled)
    }
}
