import XCTest
@testable import LLMWikiDaemon

final class DaemonConfigurationTests: XCTestCase {
    func testParsesEnvironmentAndLetsArgumentsOverrideIt() throws {
        let configuration = try DaemonConfiguration.parse(
            arguments: ["--agent", "codex", "--poll-interval", "2.5"],
            environment: [
                "LLM_WIKI_VAULT": "/srv/wiki",
                "LLM_WIKI_AGENT": "claude",
                "LLM_WIKI_MODEL": "gpt-5.6-sol"
            ]
        )

        XCTAssertEqual(configuration.vaultURL.path, "/srv/wiki")
        XCTAssertEqual(configuration.agentID, .codex)
        XCTAssertEqual(configuration.modelName, "gpt-5.6-sol")
        XCTAssertEqual(configuration.pollInterval, 2.5)
        XCTAssertEqual(configuration.permissionMode, .codexWorkspaceWrite)
    }

    func testRejectsPermissionModeForTheWrongAgent() {
        XCTAssertThrowsError(
            try DaemonConfiguration.parse(
                arguments: ["--vault", "/srv/wiki", "--agent", "codex", "--permission-mode", "acceptEdits"],
                environment: [:]
            )
        )
    }

    func testBlankStoredPromptFallsBackToSourceSpecificDefault() {
        let prompt = renderDaemonPrompt(
            storedPrompt: "  \n",
            relativePath: "raw/source.md",
            ingestDepth: .fast
        )

        XCTAssertTrue(prompt.contains("Ingest the new source at `raw/source.md`"))
        XCTAssertTrue(prompt.contains("Ingest mode: Fast"))
    }

    func testRejectsUnsupportedModelEffortAndInfiniteDurations() {
        XCTAssertThrowsError(
            try DaemonConfiguration.parse(
                arguments: [
                    "--vault", "/srv/wiki", "--agent", "codex",
                    "--model", "gpt-5.5", "--reasoning-effort", "ultra"
                ],
                environment: [:]
            )
        )
        XCTAssertThrowsError(
            try DaemonConfiguration.parse(
                arguments: ["--vault", "/srv/wiki", "--poll-interval", "inf"],
                environment: [:]
            )
        )
        XCTAssertThrowsError(
            try DaemonConfiguration.parse(
                arguments: ["--vault", "/srv/wiki", "--retry-backoff", "inf"],
                environment: [:]
            )
        )
    }
}
