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

    public var adapter: any IngestAgent {
        switch self {
        case .claude: ClaudeCodeAgent()
        case .codex: CodexAgent()
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
        permissionMode: PermissionMode
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
        permissionMode: PermissionMode
    ) -> [String] {
        let mode = AgentID.claude.allowedPermissionModes.contains(permissionMode)
            ? permissionMode
            : AgentID.claude.defaultPermissionMode

        return [
            binary.path,
            "-p",
            prompt,
            "--permission-mode",
            mode.rawValue
        ]
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
        permissionMode: PermissionMode
    ) -> [String] {
        let mode = AgentID.codex.allowedPermissionModes.contains(permissionMode)
            ? permissionMode
            : AgentID.codex.defaultPermissionMode

        return [
            binary.path,
            "exec",
            "--skip-git-repo-check",
            "--sandbox",
            mode.rawValue,
            prompt
        ]
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
