import Foundation

public struct OperationalLogRecord: Codable, Equatable {
    public var timestamp: Date
    public var agentId: AgentID
    public var file: String
    public var stream: String
    public var message: String

    public init(timestamp: Date, agentId: AgentID, file: String, stream: String, message: String) {
        self.timestamp = timestamp
        self.agentId = agentId
        self.file = file
        self.stream = stream
        self.message = message
    }
}

public actor OperationalLogger {
    private let fileURL: URL
    private let encoder: JSONEncoder

    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
    }

    public func append(_ record: OperationalLogRecord) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let data = try encoder.encode(record)
            var line = data
            line.append(0x0A)

            if FileManager.default.fileExists(atPath: fileURL.path) {
                let handle = try FileHandle(forWritingTo: fileURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
                try handle.close()
            } else {
                try line.write(to: fileURL, options: .atomic)
            }
        } catch {
            // Operational logging must never interrupt an ingest.
        }
    }
}
