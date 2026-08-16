import Foundation

public enum AgentID: String, Codable, CaseIterable, Identifiable {
    case claude
    case codex
    case pi

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "OpenAI Codex"
        case .pi: "Pi"
        }
    }

    public var schemaFilename: String {
        switch self {
        case .claude: "CLAUDE.md"
        case .codex, .pi: "AGENTS.md"
        }
    }

    public var defaultBinaryName: String {
        switch self {
        case .claude: "claude"
        case .codex: "codex"
        case .pi: "pi"
        }
    }

    public var defaultPermissionMode: PermissionMode {
        switch self {
        case .claude: .claudeAcceptEdits
        case .codex: .codexWorkspaceWrite
        case .pi: .piFullAccess
        }
    }

    public var defaultModelName: String {
        self == .pi ? "cpa/gpt-5.6-sol" : ""
    }

    public var defaultReasoningEffort: ReasoningEffort {
        self == .pi ? .high : .systemDefault
    }

    public var allowedPermissionModes: [PermissionMode] {
        switch self {
        case .claude: [.claudeAcceptEdits, .claudeDangerouslySkipPermissions]
        case .codex: [.codexWorkspaceWrite, .codexDangerFullAccess]
        case .pi: [.piFullAccess]
        }
    }

    public var availableModels: [AgentModel] {
        AgentModelCatalog.models(for: self)
    }

    /// Union of the effort levels any of this agent's models accept. Used for
    /// custom model names, where the exact model's capabilities are unknown.
    public var allowedReasoningEfforts: [ReasoningEffort] {
        if self == .pi {
            return [.systemDefault, .off, .minimal, .low, .medium, .high, .xhigh, .max]
        }
        let supported = Set(availableModels.flatMap(\.supportedEfforts))
        return [.systemDefault] + ReasoningEffort.allCases.filter {
            $0 != .systemDefault && supported.contains($0)
        }
    }

    public var adapter: any IngestAgent {
        switch self {
        case .claude: ClaudeCodeAgent()
        case .codex: CodexAgent()
        case .pi: PiAgent()
        }
    }
}

public enum IngestDepth: String, Codable, CaseIterable, Identifiable {
    case fast
    case normal
    case deep

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .fast: "Fast"
        case .normal: "Normal"
        case .deep: "Deep"
        }
    }

    public var promptDirective: String {
        switch self {
        case .fast:
            """
            Ingest mode: Fast. Prioritize getting the source filed quickly. Create or update the source page, update `wiki/index.md`, and append to `wiki/log.md`. Only update entity, concept, or synthesis pages when the source introduces a major new fact or contradiction.
            """
        case .normal:
            """
            Ingest mode: Normal. File the source, update `wiki/index.md` and `wiki/log.md`, and update the most relevant entity or concept pages. Keep the pass focused; avoid broad synthesis unless the source clearly warrants it.
            """
        case .deep:
            """
            Ingest mode: Deep. Perform a full LLM Wiki ingest: source page, index, log, relevant entity and concept pages, contradictions, cross-references, and synthesis updates when useful.
            """
        }
    }
}

public enum ReasoningEffort: String, Codable, CaseIterable, Identifiable, Sendable {
    case systemDefault
    case off
    case minimal
    case low
    case medium
    case high
    case xhigh
    case max
    case ultra

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .systemDefault: "System default"
        case .off: "Off"
        case .minimal: "Minimal"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .xhigh: "XHigh"
        case .max: "Max"
        case .ultra: "Ultra"
        }
    }

    public var cliValue: String? {
        switch self {
        case .systemDefault: nil
        case .off: "off"
        case .minimal: "minimal"
        case .low: "low"
        case .medium: "medium"
        case .high: "high"
        case .xhigh: "xhigh"
        case .ultra: "ultra"
        case .max: "max"
        }
    }
}

public enum PermissionMode: String, Codable, CaseIterable, Identifiable {
    case claudeAcceptEdits = "acceptEdits"
    case claudeDangerouslySkipPermissions = "dangerously-skip-permissions"
    case codexWorkspaceWrite = "workspace-write"
    case codexDangerFullAccess = "danger-full-access"
    case piFullAccess = "full-access"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claudeAcceptEdits: "acceptEdits"
        case .claudeDangerouslySkipPermissions: "dangerously-skip-permissions"
        case .codexWorkspaceWrite: "workspace-write"
        case .codexDangerFullAccess: "danger-full-access"
        case .piFullAccess: "Full access (Pi default)"
        }
    }

    public var isDangerous: Bool {
        switch self {
        case .claudeDangerouslySkipPermissions, .codexDangerFullAccess, .piFullAccess:
            true
        case .claudeAcceptEdits, .codexWorkspaceWrite:
            false
        }
    }
}

public protocol IngestAgent {
    var id: String { get }
    var displayName: String { get }
    var schemaFilename: String { get }
    var defaultBinaryName: String { get }

    func detectBinary() -> URL?
    func makeIngestInvocation(
        binary: URL,
        vaultRoot: URL,
        prompt: String,
        permissionMode: PermissionMode,
        modelName: String,
        reasoningEffort: ReasoningEffort
    ) -> [String]
}

public struct ClaudeCodeAgent: IngestAgent {
    public let id = "claude"
    public let displayName = "Claude Code"
    public let schemaFilename = "CLAUDE.md"
    public let defaultBinaryName = "claude"

    public init() {}

    public func detectBinary() -> URL? {
        BinaryLocator.find(defaultBinaryName)
    }

    public func makeIngestInvocation(
        binary: URL,
        vaultRoot: URL,
        prompt: String,
        permissionMode: PermissionMode,
        modelName: String = "",
        reasoningEffort: ReasoningEffort = .systemDefault
    ) -> [String] {
        let mode = AgentID.claude.allowedPermissionModes.contains(permissionMode)
            ? permissionMode
            : AgentID.claude.defaultPermissionMode

        var invocation = [
            binary.path,
            "-p",
            prompt,
            "--permission-mode",
            mode.rawValue
        ]

        let trimmedModelName = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedModelName.isEmpty {
            invocation.append(contentsOf: ["--model", trimmedModelName])
        }

        let allowedEfforts = AgentModelCatalog.allowedReasoningEfforts(
            forModelNamed: trimmedModelName,
            agentID: .claude
        )
        if let effort = reasoningEffort.cliValue, allowedEfforts.contains(reasoningEffort) {
            invocation.append(contentsOf: ["--effort", effort])
        }

        return invocation
    }
}

public struct CodexAgent: IngestAgent {
    public let id = "codex"
    public let displayName = "OpenAI Codex"
    public let schemaFilename = "AGENTS.md"
    public let defaultBinaryName = "codex"

    public init() {}

    public func detectBinary() -> URL? {
        BinaryLocator.find(defaultBinaryName)
    }

    public func makeIngestInvocation(
        binary: URL,
        vaultRoot: URL,
        prompt: String,
        permissionMode: PermissionMode,
        modelName: String = "",
        reasoningEffort: ReasoningEffort = .systemDefault
    ) -> [String] {
        let mode = AgentID.codex.allowedPermissionModes.contains(permissionMode)
            ? permissionMode
            : AgentID.codex.defaultPermissionMode

        var invocation = [
            binary.path,
            "exec",
            "--skip-git-repo-check",
            "--sandbox",
            mode.rawValue
        ]

        let trimmedModelName = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedModelName.isEmpty {
            invocation.append(contentsOf: ["--model", trimmedModelName])
        }

        let allowedEfforts = AgentModelCatalog.allowedReasoningEfforts(
            forModelNamed: trimmedModelName,
            agentID: .codex
        )
        if let effort = reasoningEffort.cliValue, allowedEfforts.contains(reasoningEffort) {
            invocation.append(contentsOf: ["-c", "model_reasoning_effort=\"\(effort)\""])
        }

        invocation.append(prompt)
        return invocation
    }
}

public struct PiAgent: IngestAgent {
    public let id = "pi"
    public let displayName = "Pi"
    public let schemaFilename = "AGENTS.md"
    public let defaultBinaryName = "pi"

    public init() {}

    public func detectBinary() -> URL? {
        BinaryLocator.find(defaultBinaryName)
    }

    public func makeIngestInvocation(
        binary: URL,
        vaultRoot: URL,
        prompt: String,
        permissionMode: PermissionMode,
        modelName: String = "",
        reasoningEffort: ReasoningEffort = .systemDefault
    ) -> [String] {
        var invocation = [binary.path, "-p", "--no-session", "--no-approve"]

        let trimmedModelName = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedModelName.isEmpty {
            invocation.append(contentsOf: ["--model", trimmedModelName])
        }

        if let effort = reasoningEffort.cliValue,
           AgentID.pi.allowedReasoningEfforts.contains(reasoningEffort) {
            invocation.append(contentsOf: ["--thinking", effort])
        }

        // Pi treats leading "-" as an option and leading "@" as a file argument.
        invocation.append(prompt.hasPrefix("-") || prompt.hasPrefix("@") ? "\n\(prompt)" : prompt)
        return invocation
    }
}

public enum BinaryLocator {
    public static func find(_ binaryName: String, environmentPath: String? = nil) -> URL? {
        guard !binaryName.contains("/") else {
            let url = URL(fileURLWithPath: binaryName)
            return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
        }

        let pathValue = environmentPath ?? ProcessInfo.processInfo.environment["PATH"] ?? ""
        var directories = pathValue
            .split(separator: ":", omittingEmptySubsequences: true)
            .map(String.init)

        let home = NSHomeDirectory()
        // The self-updating standalone installs (~/.local/bin) track new models
        // faster than the Homebrew cask, so prefer them during detection.
        for fallback in ["\(home)/.local/bin", "\(home)/.codex/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"] {
            if !directories.contains(fallback) {
                directories.append(fallback)
            }
        }

        for directory in directories {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(binaryName)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        return nil
    }
}
