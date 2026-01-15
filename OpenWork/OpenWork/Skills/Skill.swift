import Foundation

/// Protocol defining a skill that extends agent capabilities
protocol Skill: Identifiable {
    /// Unique identifier for the skill
    var id: String { get }

    /// Human-readable name
    var name: String { get }

    /// Description of what this skill does
    var description: String { get }

    /// Icon name (SF Symbols) for UI display
    var icon: String { get }

    /// Category for grouping skills
    var category: SkillCategory { get }

    /// Additional system prompt content when this skill is active
    var systemPromptAddition: String { get }

    /// Tools provided by this skill (registered when skill is activated)
    var tools: [any Tool] { get }

    /// Whether this skill is enabled by default
    var enabledByDefault: Bool { get }

    /// Optional configuration required for this skill
    var requiredConfiguration: [SkillConfigOption] { get }
}

/// Default implementations
extension Skill {
    var enabledByDefault: Bool { false }
    var requiredConfiguration: [SkillConfigOption] { [] }
}

/// Categories for organizing skills
enum SkillCategory: String, CaseIterable, Codable {
    case productivity = "Productivity"
    case development = "Development"
    case research = "Research"
    case communication = "Communication"
    case creative = "Creative"
    case data = "Data"
    case system = "System"

    var icon: String {
        switch self {
        case .productivity: return "briefcase"
        case .development: return "chevron.left.forwardslash.chevron.right"
        case .research: return "magnifyingglass"
        case .communication: return "bubble.left.and.bubble.right"
        case .creative: return "paintbrush"
        case .data: return "chart.bar"
        case .system: return "gearshape"
        }
    }
}

/// Configuration option for skills that need setup
struct SkillConfigOption: Identifiable {
    let id: String
    let name: String
    let description: String
    let type: ConfigType
    let required: Bool
    var defaultValue: String?

    enum ConfigType {
        case text
        case password
        case url
        case boolean
        case selection([String])
    }
}

/// Stored skill configuration
struct SkillConfiguration: Codable {
    var skillId: String
    var isEnabled: Bool
    var settings: [String: String]

    init(skillId: String, isEnabled: Bool = false, settings: [String: String] = [:]) {
        self.skillId = skillId
        self.isEnabled = isEnabled
        self.settings = settings
    }
}

/// Skill activation state for a session
struct ActiveSkill {
    let skill: any Skill
    let activatedAt: Date
    var configuration: SkillConfiguration
}
