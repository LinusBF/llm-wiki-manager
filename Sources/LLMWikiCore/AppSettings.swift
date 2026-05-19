import Combine
import Foundation

public enum NotificationMode: String, Codable, CaseIterable, Identifiable {
    case everyIngest
    case errorsOnly
    case never

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .everyIngest: "Every ingest"
        case .errorsOnly: "Errors only"
        case .never: "Never"
        }
    }
}

@MainActor
public final class AppSettings: ObservableObject {
    private enum Keys {
        static let activeAgentID = "activeAgentID"
        static let vaultBookmarkData = "vaultBookmarkData"
        static let vaultPath = "vaultPath"
        static let claudeBinaryPath = "claudeBinaryPath"
        static let codexBinaryPath = "codexBinaryPath"
        static let claudePermissionMode = "claudePermissionMode"
        static let codexPermissionMode = "codexPermissionMode"
        static let claudeModelName = "claudeModelName"
        static let codexModelName = "codexModelName"
        static let claudeReasoningEffort = "claudeReasoningEffort"
        static let codexReasoningEffort = "codexReasoningEffort"
        static let ingestDepth = "ingestDepth"
        static let promptTemplate = "promptTemplate"
        static let maxRetries = "maxRetries"
        static let retryBackoffSeconds = "retryBackoffSeconds"
        static let notificationMode = "notificationMode"
        static let launchAtLogin = "launchAtLogin"
    }

    public let defaults: UserDefaults

    @Published public var activeAgentID: AgentID {
        didSet { defaults.set(activeAgentID.rawValue, forKey: Keys.activeAgentID) }
    }

    @Published public var vaultBookmarkData: Data? {
        didSet { defaults.set(vaultBookmarkData, forKey: Keys.vaultBookmarkData) }
    }

    @Published public var vaultPath: String {
        didSet { defaults.set(vaultPath, forKey: Keys.vaultPath) }
    }

    @Published public var claudeBinaryPath: String {
        didSet { defaults.set(claudeBinaryPath, forKey: Keys.claudeBinaryPath) }
    }

    @Published public var codexBinaryPath: String {
        didSet { defaults.set(codexBinaryPath, forKey: Keys.codexBinaryPath) }
    }

    @Published public var claudePermissionMode: PermissionMode {
        didSet { defaults.set(claudePermissionMode.rawValue, forKey: Keys.claudePermissionMode) }
    }

    @Published public var codexPermissionMode: PermissionMode {
        didSet { defaults.set(codexPermissionMode.rawValue, forKey: Keys.codexPermissionMode) }
    }

    @Published public var claudeModelName: String {
        didSet { defaults.set(claudeModelName, forKey: Keys.claudeModelName) }
    }

    @Published public var codexModelName: String {
        didSet { defaults.set(codexModelName, forKey: Keys.codexModelName) }
    }

    @Published public var claudeReasoningEffort: ReasoningEffort {
        didSet { defaults.set(claudeReasoningEffort.rawValue, forKey: Keys.claudeReasoningEffort) }
    }

    @Published public var codexReasoningEffort: ReasoningEffort {
        didSet { defaults.set(codexReasoningEffort.rawValue, forKey: Keys.codexReasoningEffort) }
    }

    @Published public var ingestDepth: IngestDepth {
        didSet { defaults.set(ingestDepth.rawValue, forKey: Keys.ingestDepth) }
    }

    @Published public var promptTemplate: String {
        didSet { defaults.set(promptTemplate, forKey: Keys.promptTemplate) }
    }

    @Published public var maxRetries: Int {
        didSet { defaults.set(maxRetries, forKey: Keys.maxRetries) }
    }

    @Published public var retryBackoffSeconds: Double {
        didSet { defaults.set(retryBackoffSeconds, forKey: Keys.retryBackoffSeconds) }
    }

    @Published public var notificationMode: NotificationMode {
        didSet { defaults.set(notificationMode.rawValue, forKey: Keys.notificationMode) }
    }

    @Published public var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Keys.launchAtLogin) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let activeRaw = defaults.string(forKey: Keys.activeAgentID)
        self.activeAgentID = activeRaw.flatMap(AgentID.init(rawValue:)) ?? .claude

        self.vaultBookmarkData = defaults.data(forKey: Keys.vaultBookmarkData)
        self.vaultPath = defaults.string(forKey: Keys.vaultPath) ?? ""
        self.claudeBinaryPath = defaults.string(forKey: Keys.claudeBinaryPath) ?? ""
        self.codexBinaryPath = defaults.string(forKey: Keys.codexBinaryPath) ?? ""

        let claudeModeRaw = defaults.string(forKey: Keys.claudePermissionMode)
        self.claudePermissionMode = claudeModeRaw.flatMap(PermissionMode.init(rawValue:)) ?? .claudeAcceptEdits

        let codexModeRaw = defaults.string(forKey: Keys.codexPermissionMode)
        self.codexPermissionMode = codexModeRaw.flatMap(PermissionMode.init(rawValue:)) ?? .codexWorkspaceWrite

        self.claudeModelName = defaults.string(forKey: Keys.claudeModelName) ?? ""
        self.codexModelName = defaults.string(forKey: Keys.codexModelName) ?? ""

        let claudeEffortRaw = defaults.string(forKey: Keys.claudeReasoningEffort)
        self.claudeReasoningEffort = claudeEffortRaw.flatMap(ReasoningEffort.init(rawValue:)) ?? .systemDefault

        let codexEffortRaw = defaults.string(forKey: Keys.codexReasoningEffort)
        self.codexReasoningEffort = codexEffortRaw.flatMap(ReasoningEffort.init(rawValue:)) ?? .systemDefault

        let ingestDepthRaw = defaults.string(forKey: Keys.ingestDepth)
        self.ingestDepth = ingestDepthRaw.flatMap(IngestDepth.init(rawValue:)) ?? .normal

        self.promptTemplate = defaults.string(forKey: Keys.promptTemplate) ?? Self.defaultPromptTemplate
        self.maxRetries = defaults.object(forKey: Keys.maxRetries) as? Int ?? 3
        self.retryBackoffSeconds = defaults.object(forKey: Keys.retryBackoffSeconds) as? Double ?? 10

        let notificationRaw = defaults.string(forKey: Keys.notificationMode)
        self.notificationMode = notificationRaw.flatMap(NotificationMode.init(rawValue:)) ?? .errorsOnly

        self.launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
    }

    public static let defaultPromptTemplate = """
    Ingest the new source at `{file}` following the LLM Wiki pattern described in the schema file at the vault root. Read it, summarize it as a new wiki page, update relevant entity and concept pages, update `wiki/index.md`, and append an entry to `wiki/log.md`.
    """

    public func setVaultURL(_ url: URL) throws {
        vaultBookmarkData = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        vaultPath = url.path
    }

    public func resolvedVaultURL() -> URL? {
        if let vaultBookmarkData {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: vaultBookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                _ = url.startAccessingSecurityScopedResource()
                return url
            }
        }

        guard !vaultPath.isEmpty else { return nil }
        return URL(fileURLWithPath: vaultPath)
    }

    public func permissionMode(for agentID: AgentID) -> PermissionMode {
        switch agentID {
        case .claude: claudePermissionMode
        case .codex: codexPermissionMode
        }
    }

    public func setPermissionMode(_ mode: PermissionMode, for agentID: AgentID) {
        guard agentID.allowedPermissionModes.contains(mode) else { return }

        switch agentID {
        case .claude: claudePermissionMode = mode
        case .codex: codexPermissionMode = mode
        }
    }

    public func modelName(for agentID: AgentID) -> String {
        switch agentID {
        case .claude: claudeModelName
        case .codex: codexModelName
        }
    }

    public func setModelName(_ modelName: String, for agentID: AgentID) {
        switch agentID {
        case .claude: claudeModelName = modelName
        case .codex: codexModelName = modelName
        }
    }

    public func reasoningEffort(for agentID: AgentID) -> ReasoningEffort {
        let effort: ReasoningEffort
        switch agentID {
        case .claude: effort = claudeReasoningEffort
        case .codex: effort = codexReasoningEffort
        }

        return agentID.allowedReasoningEfforts.contains(effort) ? effort : .systemDefault
    }

    public func setReasoningEffort(_ effort: ReasoningEffort, for agentID: AgentID) {
        guard agentID.allowedReasoningEfforts.contains(effort) else { return }

        switch agentID {
        case .claude: claudeReasoningEffort = effort
        case .codex: codexReasoningEffort = effort
        }
    }

    public func binaryOverride(for agentID: AgentID) -> String {
        switch agentID {
        case .claude: claudeBinaryPath
        case .codex: codexBinaryPath
        }
    }

    public func setBinaryOverride(_ path: String, for agentID: AgentID) {
        switch agentID {
        case .claude: claudeBinaryPath = path
        case .codex: codexBinaryPath = path
        }
    }

    public func binaryURL(for agentID: AgentID) -> URL? {
        let override = binaryOverride(for: agentID).trimmingCharacters(in: .whitespacesAndNewlines)
        if !override.isEmpty {
            let url = URL(fileURLWithPath: override)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
        }

        return agentID.adapter.detectBinary()
    }
}
