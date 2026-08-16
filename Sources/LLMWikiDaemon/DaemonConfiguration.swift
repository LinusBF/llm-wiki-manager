import Foundation
import LLMWikiCore

enum DaemonConfigurationError: LocalizedError, Equatable {
    case helpRequested
    case missingValue(String)
    case unknownOption(String)
    case invalidValue(option: String, value: String)
    case missingVault

    var errorDescription: String? {
        switch self {
        case .helpRequested:
            return nil
        case let .missingValue(option):
            return "Missing value for \(option)."
        case let .unknownOption(option):
            return "Unknown option: \(option)."
        case let .invalidValue(option, value):
            return "Invalid value for \(option): \(value)."
        case .missingVault:
            return "Set --vault or LLM_WIKI_VAULT."
        }
    }
}

struct DaemonConfiguration: Equatable {
    let vaultURL: URL
    let agentID: AgentID
    let binaryURL: URL?
    let modelName: String
    let reasoningEffort: ReasoningEffort
    let ingestDepth: IngestDepth
    let permissionMode: PermissionMode
    let pollInterval: TimeInterval
    let maxRetries: Int
    let retryBackoff: TimeInterval

    static let usage = """
    Usage: llm-wiki-daemon --vault PATH [options]

      --agent claude|codex
      --binary PATH
      --model NAME
      --reasoning-effort system-default|low|medium|high|xhigh|max|ultra
      --ingest-depth fast|normal|deep
      --permission-mode MODE
      --poll-interval SECONDS
      --max-retries COUNT
      --retry-backoff SECONDS

    Every option is also available through LLM_WIKI_* environment variables.
    See Packaging/llm-wiki-manager.env.example for the complete list.
    """

    static func parse(
        arguments: [String] = Array(CommandLine.arguments.dropFirst()),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> DaemonConfiguration {
        var options: [String: String] = [:]
        var index = 0
        let allowed = Set([
            "--vault", "--agent", "--binary", "--model", "--reasoning-effort",
            "--ingest-depth", "--permission-mode", "--poll-interval",
            "--max-retries", "--retry-backoff"
        ])

        while index < arguments.count {
            let option = arguments[index]
            if option == "--help" || option == "-h" {
                throw DaemonConfigurationError.helpRequested
            }
            guard allowed.contains(option) else {
                throw DaemonConfigurationError.unknownOption(option)
            }
            index += 1
            guard index < arguments.count else {
                throw DaemonConfigurationError.missingValue(option)
            }
            options[option] = arguments[index]
            index += 1
        }

        func value(_ option: String, _ environmentKey: String, default defaultValue: String = "") -> String {
            options[option] ?? environment[environmentKey] ?? defaultValue
        }

        let vaultPath = value("--vault", "LLM_WIKI_VAULT")
        guard !vaultPath.isEmpty else { throw DaemonConfigurationError.missingVault }

        let agentValue = value("--agent", "LLM_WIKI_AGENT", default: "claude")
        guard let agentID = AgentID(rawValue: agentValue) else {
            throw DaemonConfigurationError.invalidValue(option: "--agent", value: agentValue)
        }

        let effortValue = value("--reasoning-effort", "LLM_WIKI_REASONING_EFFORT", default: "system-default")
        let reasoningEffort = effortValue == "system-default"
            ? ReasoningEffort.systemDefault
            : ReasoningEffort(rawValue: effortValue)
        guard let reasoningEffort else {
            throw DaemonConfigurationError.invalidValue(option: "--reasoning-effort", value: effortValue)
        }
        let modelName = value("--model", "LLM_WIKI_MODEL")
        guard AgentModelCatalog.allowedReasoningEfforts(
            forModelNamed: modelName,
            agentID: agentID
        ).contains(reasoningEffort) else {
            throw DaemonConfigurationError.invalidValue(option: "--reasoning-effort", value: effortValue)
        }

        let depthValue = value("--ingest-depth", "LLM_WIKI_INGEST_DEPTH", default: "normal")
        guard let ingestDepth = IngestDepth(rawValue: depthValue) else {
            throw DaemonConfigurationError.invalidValue(option: "--ingest-depth", value: depthValue)
        }

        let permissionValue = value(
            "--permission-mode",
            "LLM_WIKI_PERMISSION_MODE",
            default: agentID.defaultPermissionMode.rawValue
        )
        guard let permissionMode = PermissionMode(rawValue: permissionValue),
              agentID.allowedPermissionModes.contains(permissionMode) else {
            throw DaemonConfigurationError.invalidValue(option: "--permission-mode", value: permissionValue)
        }

        let pollValue = value("--poll-interval", "LLM_WIKI_POLL_INTERVAL", default: "5")
        guard let pollInterval = TimeInterval(pollValue), pollInterval.isFinite, pollInterval > 0 else {
            throw DaemonConfigurationError.invalidValue(option: "--poll-interval", value: pollValue)
        }

        let retriesValue = value("--max-retries", "LLM_WIKI_MAX_RETRIES", default: "3")
        guard let maxRetries = Int(retriesValue), maxRetries > 0 else {
            throw DaemonConfigurationError.invalidValue(option: "--max-retries", value: retriesValue)
        }

        let backoffValue = value("--retry-backoff", "LLM_WIKI_RETRY_BACKOFF", default: "10")
        guard let retryBackoff = TimeInterval(backoffValue), retryBackoff.isFinite, retryBackoff >= 0 else {
            throw DaemonConfigurationError.invalidValue(option: "--retry-backoff", value: backoffValue)
        }

        let binaryPath = value("--binary", "LLM_WIKI_BINARY")
        return DaemonConfiguration(
            vaultURL: URL(fileURLWithPath: vaultPath).standardizedFileURL,
            agentID: agentID,
            binaryURL: binaryPath.isEmpty ? nil : URL(fileURLWithPath: binaryPath),
            modelName: modelName,
            reasoningEffort: reasoningEffort,
            ingestDepth: ingestDepth,
            permissionMode: permissionMode,
            pollInterval: pollInterval,
            maxRetries: maxRetries,
            retryBackoff: retryBackoff
        )
    }
}

func renderDaemonPrompt(storedPrompt: String?, relativePath: String, ingestDepth: IngestDepth) -> String {
    let prompt = storedPrompt.flatMap {
        $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0
    } ?? defaultIngestPrompt
    return """
    \(prompt.replacingOccurrences(of: "{file}", with: relativePath))

    \(ingestDepth.promptDirective)
    """
}
