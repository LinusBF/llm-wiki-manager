import Foundation
import LLMWikiCore

#if os(Linux)
import Glibc
#else
import Darwin
#endif

@main
struct LLMWikiDaemonMain {
    static func main() async {
        do {
            let configuration = try DaemonConfiguration.parse()
            let daemon = try WikiDaemon(configuration: configuration)
            try await daemon.run()
        } catch DaemonConfigurationError.helpRequested {
            print(DaemonConfiguration.usage)
        } catch {
            writeError("llm-wiki-daemon: \(error.localizedDescription)\n\n\(DaemonConfiguration.usage)\n")
            exit(2)
        }
    }

    private static func writeError(_ message: String) {
        try? FileHandle.standardError.write(contentsOf: Data(message.utf8))
    }
}

private final class WikiDaemon {
    private let configuration: DaemonConfiguration
    private let paths: WikiPaths
    private let scanner = SourceScanner()
    private let runner = ProcessRunner()
    private let logger: OperationalLogger
    private let binary: URL
    private var exhaustedSources = Set<String>()
    private var observedSources: [String: SourceFingerprint] = [:]

    init(configuration: DaemonConfiguration) throws {
        self.configuration = configuration
        paths = WikiPaths(vaultRoot: configuration.vaultURL)
        logger = OperationalLogger(fileURL: paths.appLog)

        let candidate = configuration.binaryURL ?? configuration.agentID.adapter.detectBinary()
        guard let candidate, FileManager.default.isExecutableFile(atPath: candidate.path) else {
            throw ProcessRunnerError.executableMissing(
                configuration.binaryURL?.path ?? configuration.agentID.defaultBinaryName
            )
        }
        binary = candidate
    }

    func run() async throws {
        try paths.ensureVaultDirectories()
        try paths.ensurePromptFile(defaultPrompt: defaultIngestPrompt)
        try DefaultSchema.writeStarterSchemasIfMissing(in: paths)

        print("Watching \(paths.raw.path) with \(configuration.agentID.displayName)")

        while true {
            do {
                let sources = try scanner.pendingSources(in: paths)
                let currentPaths = Set(sources.map(\.path))
                observedSources = observedSources.filter { currentPaths.contains($0.key) }

                for source in sources {
                    let fingerprint = SourceFingerprint(source)
                    let previous = observedSources.updateValue(fingerprint, forKey: source.path)
                    guard previous == fingerprint else {
                        exhaustedSources.remove(source.path)
                        continue
                    }
                    guard !exhaustedSources.contains(source.path) else { continue }

                    if !(await ingest(source, fingerprint: fingerprint)) {
                        exhaustedSources.insert(source.path)
                    }
                }
            } catch {
                Self.error("Scan failed: \(error.localizedDescription)")
            }

            try? await Task.sleep(for: .seconds(configuration.pollInterval))
        }
    }

    private func ingest(_ source: URL, fingerprint: SourceFingerprint) async -> Bool {
        for attempt in 1...configuration.maxRetries {
            print("Ingesting \(source.lastPathComponent) (attempt \(attempt)/\(configuration.maxRetries))")
            let before = WikiDirectorySnapshot(wikiURL: paths.wiki)
            let prompt = renderedPrompt(for: source)
            let invocation = configuration.agentID.adapter.makeIngestInvocation(
                binary: binary,
                vaultRoot: paths.vaultRoot,
                prompt: prompt,
                permissionMode: configuration.permissionMode,
                modelName: configuration.modelName,
                reasoningEffort: configuration.reasoningEffort
            )

            do {
                let result = try await runner.run(invocation: invocation, currentDirectory: paths.vaultRoot) {
                    [logger, agentID = configuration.agentID, relativeFile = paths.relativePath(for: source)] line in
                    Self.output(line)
                    Task {
                        await logger.append(
                            OperationalLogRecord(
                                timestamp: line.timestamp,
                                agentId: agentID,
                                file: relativeFile,
                                stream: line.stream,
                                message: line.text
                            )
                        )
                    }
                }

                if result.exitCode == 0 {
                    guard SourceFingerprint(source) == fingerprint else {
                        Self.error("Source changed during ingest; leaving \(source.lastPathComponent) unmarked")
                        return true
                    }
                    switch await writeMarker(for: source, fingerprint: fingerprint) {
                    case .sourceChanged:
                        Self.error("Source changed after ingest; leaving \(source.lastPathComponent) unmarked")
                        return true
                    case .failed:
                        return false
                    case .written:
                        break
                    }
                    let changed = WikiDirectorySnapshot(wikiURL: paths.wiki).changedFileCount(comparedTo: before)
                    print("Ingested \(source.lastPathComponent); \(changed) wiki page(s) changed")
                    return true
                }
                Self.error("Agent exited with code \(result.exitCode) for \(source.lastPathComponent)")
            } catch {
                Self.error("Ingest failed for \(source.lastPathComponent): \(error.localizedDescription)")
            }

            guard SourceFingerprint(source) == fingerprint else {
                Self.error("Source changed during ingest; restarting after it stabilizes")
                return true
            }
            guard attempt < configuration.maxRetries else { return false }
            try? await Task.sleep(for: .seconds(retryDelay(for: attempt)))
        }
        return false
    }

    private func writeMarker(for source: URL, fingerprint: SourceFingerprint) async -> MarkerWriteResult {
        for attempt in 1...configuration.maxRetries {
            guard SourceFingerprint(source) == fingerprint else { return .sourceChanged }
            do {
                let marker = paths.markerFile(for: source)
                try Data().write(to: marker, options: .atomic)
                guard SourceFingerprint(source) == fingerprint else {
                    try? FileManager.default.removeItem(at: marker)
                    return .sourceChanged
                }
                return .written
            } catch {
                Self.error(
                    "Marker write failed for \(source.lastPathComponent) "
                    + "(attempt \(attempt)/\(configuration.maxRetries)): \(error.localizedDescription)"
                )
            }

            guard attempt < configuration.maxRetries else { return .failed }
            try? await Task.sleep(for: .seconds(retryDelay(for: attempt)))
        }
        return .failed
    }

    private func retryDelay(for attempt: Int) -> TimeInterval {
        let multiplier: Double = attempt == 1 ? 1 : attempt == 2 ? 6 : 30
        return min(configuration.retryBackoff * multiplier, 3_600)
    }

    private func renderedPrompt(for source: URL) -> String {
        renderDaemonPrompt(
            storedPrompt: try? String(contentsOf: paths.ingestPrompt, encoding: .utf8),
            relativePath: paths.relativePath(for: source),
            ingestDepth: configuration.ingestDepth
        )
    }

    private static func output(_ line: ProcessOutputLine) {
        let message = "[\(line.stream)] \(line.text)\n"
        let handle = line.stream == "stderr" ? FileHandle.standardError : FileHandle.standardOutput
        try? handle.write(contentsOf: Data(message.utf8))
    }

    private static func error(_ message: String) {
        try? FileHandle.standardError.write(contentsOf: Data("llm-wiki-daemon: \(message)\n".utf8))
    }
}

private struct SourceFingerprint: Equatable {
    let size: Int?
    let modifiedAt: Date?

    init(_ url: URL) {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        size = values?.fileSize
        modifiedAt = values?.contentModificationDate
    }
}

private enum MarkerWriteResult {
    case written
    case sourceChanged
    case failed
}
