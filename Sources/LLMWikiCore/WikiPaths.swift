import Foundation

public struct WikiPaths: Equatable {
    public let vaultRoot: URL

    public init(vaultRoot: URL) {
        self.vaultRoot = vaultRoot
    }

    public var raw: URL { vaultRoot.appendingPathComponent("raw", isDirectory: true) }
    public var wiki: URL { vaultRoot.appendingPathComponent("wiki", isDirectory: true) }
    public var ingested: URL { vaultRoot.appendingPathComponent(".ingested", isDirectory: true) }
    public var appSupport: URL { vaultRoot.appendingPathComponent(".llm-wiki", isDirectory: true) }
    public var appLog: URL { appSupport.appendingPathComponent("log.jsonl") }
    public var state: URL { appSupport.appendingPathComponent("state.json") }
    public var prompts: URL { appSupport.appendingPathComponent("prompts", isDirectory: true) }
    public var ingestPrompt: URL { prompts.appendingPathComponent("ingest.txt") }

    public func schemaFile(for agentID: AgentID) -> URL {
        vaultRoot.appendingPathComponent(agentID.schemaFilename)
    }

    public func markerFile(for sourceURL: URL) -> URL {
        ingested.appendingPathComponent(sourceURL.lastPathComponent)
    }

    public func ensureVaultDirectories() throws {
        let manager = FileManager.default
        try manager.createDirectory(at: raw, withIntermediateDirectories: true)
        try manager.createDirectory(at: wiki, withIntermediateDirectories: true)
        try manager.createDirectory(at: ingested, withIntermediateDirectories: true)
        try manager.createDirectory(at: prompts, withIntermediateDirectories: true)
    }

    public func ensurePromptFile(defaultPrompt: String) throws {
        if !FileManager.default.fileExists(atPath: ingestPrompt.path) {
            try defaultPrompt.write(to: ingestPrompt, atomically: true, encoding: .utf8)
        }
    }

    public func relativePath(for url: URL) -> String {
        let root = vaultRoot.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(root + "/") else { return url.path }
        return String(path.dropFirst(root.count + 1))
    }
}
