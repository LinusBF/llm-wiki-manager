import Foundation

public enum QueueItemStatus: String, Codable, Equatable {
    case pending
    case running
    case retrying
    case failed
    case succeeded
}

public struct QueueItem: Codable, Identifiable, Equatable {
    public var id: UUID
    public var filePath: String
    public var agentId: AgentID
    public var status: QueueItemStatus
    public var attempts: Int
    public var createdAt: Date
    public var startedAt: Date?
    public var finishedAt: Date?
    public var nextRunAt: Date?
    public var lastError: String?
    public var wikiPagesUpdated: Int?
    public var durationSeconds: Double?

    public init(
        id: UUID = UUID(),
        filePath: String,
        agentId: AgentID,
        status: QueueItemStatus = .pending,
        attempts: Int = 0,
        createdAt: Date = Date(),
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        nextRunAt: Date? = nil,
        lastError: String? = nil,
        wikiPagesUpdated: Int? = nil,
        durationSeconds: Double? = nil
    ) {
        self.id = id
        self.filePath = filePath
        self.agentId = agentId
        self.status = status
        self.attempts = attempts
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.nextRunAt = nextRunAt
        self.lastError = lastError
        self.wikiPagesUpdated = wikiPagesUpdated
        self.durationSeconds = durationSeconds
    }

    public var sourceURL: URL {
        URL(fileURLWithPath: filePath)
    }
}

public struct PersistedIngestState: Codable, Equatable {
    public var queue: [QueueItem]
    public var recent: [QueueItem]

    public init(queue: [QueueItem] = [], recent: [QueueItem] = []) {
        self.queue = queue
        self.recent = recent
    }
}

public enum IngestStateStore {
    public static func load(from url: URL) throws -> PersistedIngestState {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return PersistedIngestState()
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PersistedIngestState.self, from: data)
    }

    public static func save(_ state: PersistedIngestState, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }
}
