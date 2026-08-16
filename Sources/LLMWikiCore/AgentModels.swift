import Foundation

/// A model the ingest agent CLI can be pointed at, plus the reasoning effort
/// levels that model actually accepts.
public struct AgentModel: Identifiable, Hashable, Sendable {
    /// Value passed to the CLI's `--model` flag.
    public let id: String
    public let displayName: String
    public let summary: String
    /// Effort levels the model supports, excluding `.systemDefault`.
    /// Empty means the model has no effort control at all.
    public let supportedEfforts: [ReasoningEffort]

    public init(
        id: String,
        displayName: String,
        summary: String,
        supportedEfforts: [ReasoningEffort]
    ) {
        self.id = id
        self.displayName = displayName
        self.summary = summary
        self.supportedEfforts = supportedEfforts
    }

    public var supportsReasoningEffort: Bool { !supportedEfforts.isEmpty }

    /// Everything the effort picker may offer for this model.
    public var allowedReasoningEfforts: [ReasoningEffort] {
        [.systemDefault] + supportedEfforts
    }
}

/// What the Preferences model picker currently has selected.
public enum ModelSelection: Hashable, Sendable {
    /// Let the CLI choose (no `--model` flag).
    case agentDefault
    /// One of the catalog models, by CLI model name.
    case known(String)
    /// A hand-typed model name.
    case custom

    /// Derives the picker selection from the stored model name.
    /// `forcesCustom` is set once the user has explicitly chosen "Custom…", so
    /// the text field stays visible while the field is still empty.
    public static func resolve(
        modelName: String,
        agentID: AgentID,
        forcesCustom: Bool = false
    ) -> ModelSelection {
        let trimmed = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        if forcesCustom { return .custom }
        if trimmed.isEmpty { return .agentDefault }
        guard AgentModelCatalog.model(named: trimmed, for: agentID) != nil else { return .custom }
        return .known(trimmed)
    }

    /// The model name to store for this selection. `nil` means "leave the
    /// stored name alone" — used when switching to the custom field.
    public var storedModelName: String? {
        switch self {
        case .agentDefault: ""
        case let .known(id): id
        case .custom: nil
        }
    }
}

/// The models each agent CLI currently exposes. Model lines move fast, so this
/// is a curated snapshot rather than a live query: an unknown model name typed
/// into Preferences is still passed through to the CLI untouched.
public enum AgentModelCatalog {
    /// Claude Code accepts either an alias (`opus`, `sonnet`) or a full model
    /// name. Full names are used here so the ingest is pinned to an exact model.
    public static let claude: [AgentModel] = [
        AgentModel(
            id: "claude-opus-5",
            displayName: "Claude Opus 5",
            summary: "Default pick for ingests: strongest agentic model at Opus pricing.",
            supportedEfforts: [.low, .medium, .high, .xhigh, .max]
        ),
        AgentModel(
            id: "claude-fable-5",
            displayName: "Claude Fable 5",
            summary: "Most capable, most expensive. Thinking is always on.",
            supportedEfforts: [.low, .medium, .high, .xhigh, .max]
        ),
        AgentModel(
            id: "claude-opus-4-8",
            displayName: "Claude Opus 4.8",
            summary: "Previous Opus generation.",
            supportedEfforts: [.low, .medium, .high, .xhigh, .max]
        ),
        AgentModel(
            id: "claude-sonnet-5",
            displayName: "Claude Sonnet 5",
            summary: "Near-Opus quality at Sonnet cost. Good for high-volume ingests.",
            supportedEfforts: [.low, .medium, .high, .xhigh, .max]
        ),
        AgentModel(
            id: "claude-haiku-4-5",
            displayName: "Claude Haiku 4.5",
            summary: "Fastest and cheapest. No reasoning effort control.",
            supportedEfforts: []
        )
    ]

    /// Codex slugs and their reasoning levels, matching what the Codex CLI
    /// itself offers for each model.
    public static let codex: [AgentModel] = [
        AgentModel(
            id: "gpt-5.6-sol",
            displayName: "GPT-5.6-Sol",
            summary: "Latest frontier agentic coding model.",
            supportedEfforts: [.low, .medium, .high, .xhigh, .max, .ultra]
        ),
        AgentModel(
            id: "gpt-5.6-terra",
            displayName: "GPT-5.6-Terra",
            summary: "Frontier sibling to Sol.",
            supportedEfforts: [.low, .medium, .high, .xhigh, .max, .ultra]
        ),
        AgentModel(
            id: "gpt-5.6-luna",
            displayName: "GPT-5.6-Luna",
            summary: "Lighter 5.6 model.",
            supportedEfforts: [.low, .medium, .high, .xhigh, .max]
        ),
        AgentModel(
            id: "gpt-5.5",
            displayName: "GPT-5.5",
            summary: "Previous generation.",
            supportedEfforts: [.low, .medium, .high, .xhigh]
        ),
        AgentModel(
            id: "gpt-5.4",
            displayName: "GPT-5.4",
            summary: "Older generation.",
            supportedEfforts: [.low, .medium, .high, .xhigh]
        ),
        AgentModel(
            id: "gpt-5.4-mini",
            displayName: "GPT-5.4-Mini",
            summary: "Small and cheap.",
            supportedEfforts: [.low, .medium, .high, .xhigh]
        ),
        AgentModel(
            id: "gpt-5.3-codex-spark",
            displayName: "GPT-5.3-Codex-Spark",
            summary: "Low-latency Codex model.",
            supportedEfforts: [.low, .medium, .high, .xhigh]
        )
    ]

    public static func models(for agentID: AgentID) -> [AgentModel] {
        switch agentID {
        case .claude: claude
        case .codex: codex
        case .pi: []
        }
    }

    public static func model(named modelName: String, for agentID: AgentID) -> AgentModel? {
        let trimmed = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return models(for: agentID).first { $0.id == trimmed }
    }

    /// Effort levels valid for `modelName`. Known models are constrained to the
    /// levels they actually accept; an empty name (agent default) or a custom
    /// name falls back to everything the agent's CLI understands.
    public static func allowedReasoningEfforts(
        forModelNamed modelName: String,
        agentID: AgentID
    ) -> [ReasoningEffort] {
        if let model = model(named: modelName, for: agentID) {
            return model.allowedReasoningEfforts
        }
        return agentID.allowedReasoningEfforts
    }
}
