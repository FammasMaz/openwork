import Foundation
import Combine

/// Manages skill registration, activation, and discovery
@MainActor
class SkillRegistry: ObservableObject {
    static let shared = SkillRegistry()

    @Published private(set) var availableSkills: [any Skill] = []
    @Published private(set) var activeSkills: [String: ActiveSkill] = [:]
    @Published private(set) var configurations: [String: SkillConfiguration] = [:]

    private let configKey = "OpenWork.SkillConfigurations"
    private weak var toolRegistry: ToolRegistry?

    private init() {
        registerBuiltinSkills()
        loadConfigurations()
    }

    // MARK: - Setup

    func setToolRegistry(_ registry: ToolRegistry) {
        self.toolRegistry = registry
    }

    // MARK: - Registration

    /// Registers a skill
    func register(_ skill: any Skill) {
        if !availableSkills.contains(where: { $0.id == skill.id }) {
            availableSkills.append(skill)

            // Create default configuration if needed
            if configurations[skill.id] == nil {
                configurations[skill.id] = SkillConfiguration(
                    skillId: skill.id,
                    isEnabled: skill.enabledByDefault
                )
            }
        }
    }

    /// Unregisters a skill
    func unregister(id: String) {
        availableSkills.removeAll { $0.id == id }
        deactivate(id: id)
    }

    // MARK: - Activation

    /// Activates a skill for the current session
    func activate(id: String) {
        guard let skill = availableSkills.first(where: { $0.id == id }),
              activeSkills[id] == nil else { return }

        let config = configurations[id] ?? SkillConfiguration(skillId: id, isEnabled: true)

        activeSkills[id] = ActiveSkill(
            skill: skill,
            activatedAt: Date(),
            configuration: config
        )

        // Register skill tools with tool registry
        if let toolRegistry = toolRegistry {
            for tool in skill.tools {
                toolRegistry.register(tool)
            }
        }

        // Update configuration
        var updatedConfig = config
        updatedConfig.isEnabled = true
        configurations[id] = updatedConfig
        saveConfigurations()
    }

    /// Deactivates a skill
    func deactivate(id: String) {
        guard let activeSkill = activeSkills[id] else { return }

        // Unregister skill tools
        if let toolRegistry = toolRegistry {
            for tool in activeSkill.skill.tools {
                toolRegistry.unregister(id: tool.id)
            }
        }

        activeSkills.removeValue(forKey: id)
    }

    /// Toggles skill activation
    func toggle(id: String) {
        if activeSkills[id] != nil {
            deactivate(id: id)
        } else {
            activate(id: id)
        }
    }

    // MARK: - Query

    /// Gets the combined system prompt addition from all active skills
    func combinedSystemPrompt() -> String {
        let additions = activeSkills.values
            .map { $0.skill.systemPromptAddition }
            .filter { !$0.isEmpty }

        guard !additions.isEmpty else { return "" }

        return """

        ## Active Skills

        \(additions.joined(separator: "\n\n"))
        """
    }

    /// Gets a skill by ID
    func skill(forID id: String) -> (any Skill)? {
        availableSkills.first { $0.id == id }
    }

    /// Gets skills by category
    func skills(in category: SkillCategory) -> [any Skill] {
        availableSkills.filter { $0.category == category }
    }

    /// Whether a skill is currently active
    func isActive(_ id: String) -> Bool {
        activeSkills[id] != nil
    }

    // MARK: - Configuration

    /// Updates skill configuration
    func updateConfiguration(skillId: String, settings: [String: String]) {
        var config = configurations[skillId] ?? SkillConfiguration(skillId: skillId)
        config.settings = settings
        configurations[skillId] = config
        saveConfigurations()
    }

    /// Gets configuration value for a skill
    func configValue(skillId: String, key: String) -> String? {
        configurations[skillId]?.settings[key]
    }

    // MARK: - Persistence

    private func saveConfigurations() {
        let configsArray = Array(configurations.values)
        if let data = try? JSONEncoder().encode(configsArray) {
            UserDefaults.standard.set(data, forKey: configKey)
        }
    }

    private func loadConfigurations() {
        guard let data = UserDefaults.standard.data(forKey: configKey),
              let configs = try? JSONDecoder().decode([SkillConfiguration].self, from: data) else {
            return
        }

        for config in configs {
            configurations[config.skillId] = config
        }
    }

    // MARK: - Built-in Skills

    private func registerBuiltinSkills() {
        register(DocumentSkill())
        register(CodeReviewSkill())
        register(ResearchSkill())
    }
}

// MARK: - Code Review Skill

struct CodeReviewSkill: Skill {
    let id = "code-review"
    let name = "Code Review"
    let description = "Enhanced code review capabilities with security analysis and best practices"
    let icon = "checkmark.shield"
    let category: SkillCategory = .development

    var systemPromptAddition: String {
        """
        ### Code Review Skill
        When reviewing code, follow these guidelines:
        1. Check for security vulnerabilities (OWASP Top 10)
        2. Identify performance issues and memory leaks
        3. Verify proper error handling
        4. Check for code style consistency
        5. Look for potential bugs and edge cases
        6. Suggest improvements with concrete examples
        7. Review test coverage adequacy
        """
    }

    var tools: [any Tool] { [] }
}

// MARK: - Research Skill

struct ResearchSkill: Skill {
    let id = "research"
    let name = "Research Assistant"
    let description = "Deep research capabilities with source verification and citation"
    let icon = "book.pages"
    let category: SkillCategory = .research

    var systemPromptAddition: String {
        """
        ### Research Skill
        When conducting research:
        1. Verify information from multiple sources
        2. Cite sources with URLs when available
        3. Distinguish between facts and opinions
        4. Note when information may be outdated
        5. Summarize key findings clearly
        6. Identify gaps in available information
        7. Suggest follow-up research areas
        """
    }

    var tools: [any Tool] { [] }
}
