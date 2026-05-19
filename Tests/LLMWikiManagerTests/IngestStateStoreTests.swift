import XCTest
@testable import LLMWikiCore

final class IngestStateStoreTests: XCTestCase {
    func testPersistsIngestStatsFields() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("llm-wiki-state-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let stateURL = root.appendingPathComponent("state.json")
        let item = QueueItem(
            filePath: "/tmp/vault/raw/source.md",
            agentId: .codex,
            status: .succeeded,
            attempts: 2,
            wikiPagesUpdated: 7,
            durationSeconds: 42.5,
            queuedDurationSeconds: 12.25,
            modelName: "gpt-5.4-mini",
            reasoningEffort: .low,
            ingestDepth: .fast
        )

        try IngestStateStore.save(PersistedIngestState(recent: [item]), to: stateURL)
        let loaded = try IngestStateStore.load(from: stateURL)
        let loadedItem = try XCTUnwrap(loaded.recent.first)

        XCTAssertEqual(loadedItem.wikiPagesUpdated, 7)
        XCTAssertEqual(loadedItem.durationSeconds, 42.5)
        XCTAssertEqual(loadedItem.queuedDurationSeconds, 12.25)
        XCTAssertEqual(loadedItem.modelName, "gpt-5.4-mini")
        XCTAssertEqual(loadedItem.reasoningEffort, .low)
        XCTAssertEqual(loadedItem.ingestDepth, .fast)
    }
}
