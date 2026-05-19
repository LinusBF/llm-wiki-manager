import Foundation

public enum AgentID: String, Codable, CaseIterable, Identifiable {
    case claude
    case codex

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "OpenAI Codex"
        }
    }

    public var schemaFilename: String {
        switch self {
        case .claude: "CLAUDE.md"
        case .codex: "AGENTS.md"
        }
    }

    public var defaultBinaryName: String {
        switch self {
        case .claude: "claude"
        case .codex: "codex"
        }
    }

    public var defaultPermissionMode: PermissionMode {
        switch self {
        case .claude: .claudeAcceptEdits
        case .codex: .codexWorkspaceWrite
        }
    }

    public var allowedPermissionModes: [PermissionMode] {
        switch self {
        case .claude: [.claudeAcceptEdits, .claudeDangerouslySkipPermissions]
        case .codex: [.codexWorkspaceWrite, .codexDangerFullAccess]
        }
    }

    public var allowedReasoningEfforts: [ReasoningEffort] {
        switch self {
        case .claude:
            ReasoningEffort.allCases
        case .codex:
            [.systemDefault, .low, .medium, .high, .xhigh]
        }
    }

    public var adapter: any IngestAgent {
        switch self {
        case .claude: ClaudeCodeAgent()
        case .codex: CodexAgent()
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

public enum ReasoningEffort: String, Codable, CaseIterable, Identifiable {
    case systemDefault
    case low
    case medium
    case high
    case xhigh
    case max

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .systemDefault: "System default"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .xhigh: "XHigh"
        case .max: "Max"
        }
    }

    public var cliValue: String? {
        switch self {
        case .systemDefault: nil
        case .low: "low"
        case .medium: "medium"
        case .high: "high"
        case .xhigh: "xhigh"
        case .max: "max"
        }
    }
}

public enum PermissionMode: String, Codable, CaseIterable, Identifiable {
    case claudeAcceptEdits = "acceptEdits"
    case claudeDangerouslySkipPermissions = "dangerously-skip-permissions"
    case codexWorkspaceWrite = "workspace-write"
    case codexDangerFullAccess = "danger-full-access"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claudeAcceptEdits: "acceptEdits"
        case .claudeDangerouslySkipPermissions: "dangerously-skip-permissions"
        case .codexWorkspaceWrite: "workspace-write"
        case .codexDangerFullAccess: "danger-full-access"
        }
    }

    public var isDangerous: Bool {
        switch self {
        case .claudeDangerouslySkipPermissions, .codexDangerFullAccess:
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

        if let effort = reasoningEffort.cliValue,
           AgentID.claude.allowedReasoningEfforts.contains(reasoningEffort) {
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

        if let effort = reasoningEffort.cliValue,
           AgentID.codex.allowedReasoningEfforts.contains(reasoningEffort) {
            invocation.append(contentsOf: ["-c", "model_reasoning_effort=\"\(effort)\""])
        }

        invocation.append(prompt)
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

        for fallback in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"] {
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
