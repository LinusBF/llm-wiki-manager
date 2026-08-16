import XCTest
@testable import LLMWikiCore

final class AgentInvocationTests: XCTestCase {
    func testClaudeInvocationUsesPermissionMode() {
        let binary = URL(fileURLWithPath: "/usr/local/bin/claude")
        let invocation = ClaudeCodeAgent().makeIngestInvocation(
            binary: binary,
            vaultRoot: URL(fileURLWithPath: "/tmp/vault"),
            prompt: "Ingest raw/source.md",
            permissionMode: .claudeAcceptEdits
        )

        XCTAssertEqual(invocation, [
            "/usr/local/bin/claude",
            "-p",
            "Ingest raw/source.md",
            "--permission-mode",
            "acceptEdits"
        ])
    }

    func testCodexInvocationUsesSandboxMode() {
        let binary = URL(fileURLWithPath: "/opt/homebrew/bin/codex")
        let invocation = CodexAgent().makeIngestInvocation(
            binary: binary,
            vaultRoot: URL(fileURLWithPath: "/tmp/vault"),
            prompt: "Ingest raw/source.md",
            permissionMode: .codexWorkspaceWrite
        )

        XCTAssertEqual(invocation, [
            "/opt/homebrew/bin/codex",
            "exec",
            "--skip-git-repo-check",
            "--sandbox",
            "workspace-write",
            "Ingest raw/source.md"
        ])
    }

    func testWrongPermissionModeFallsBackToAgentDefault() {
        let binary = URL(fileURLWithPath: "/opt/homebrew/bin/codex")
        let invocation = CodexAgent().makeIngestInvocation(
            binary: binary,
            vaultRoot: URL(fileURLWithPath: "/tmp/vault"),
            prompt: "Ingest",
            permissionMode: .claudeDangerouslySkipPermissions
        )

        XCTAssertEqual(invocation[4], "workspace-write")
    }

    func testClaudeInvocationIncludesModelAndEffortWhenConfigured() {
        let binary = URL(fileURLWithPath: "/usr/local/bin/claude")
        let invocation = ClaudeCodeAgent().makeIngestInvocation(
            binary: binary,
            vaultRoot: URL(fileURLWithPath: "/tmp/vault"),
            prompt: "Ingest",
            permissionMode: .claudeAcceptEdits,
            modelName: "sonnet",
            reasoningEffort: .high
        )

        XCTAssertEqual(invocation.suffix(4), ["--model", "sonnet", "--effort", "high"])
    }

    func testCodexInvocationIncludesModelAndReasoningConfigWhenConfigured() {
        let binary = URL(fileURLWithPath: "/opt/homebrew/bin/codex")
        let invocation = CodexAgent().makeIngestInvocation(
            binary: binary,
            vaultRoot: URL(fileURLWithPath: "/tmp/vault"),
            prompt: "Ingest",
            permissionMode: .codexWorkspaceWrite,
            modelName: "gpt-5.4-mini",
            reasoningEffort: .low
        )

        XCTAssertEqual(invocation, [
            "/opt/homebrew/bin/codex",
            "exec",
            "--skip-git-repo-check",
            "--sandbox",
            "workspace-write",
            "--model",
            "gpt-5.4-mini",
            "-c",
            "model_reasoning_effort=\"low\"",
            "Ingest"
        ])
    }

    func testCodexInvocationSupportsUltraReasoningEffort() {
        let binary = URL(fileURLWithPath: "/opt/homebrew/bin/codex")
        let invocation = CodexAgent().makeIngestInvocation(
            binary: binary,
            vaultRoot: URL(fileURLWithPath: "/tmp/vault"),
            prompt: "Ingest",
            permissionMode: .codexWorkspaceWrite,
            modelName: "gpt-5.6-sol",
            reasoningEffort: .ultra
        )

        XCTAssertEqual(invocation.suffix(5), [
            "--model",
            "gpt-5.6-sol",
            "-c",
            "model_reasoning_effort=\"ultra\"",
            "Ingest"
        ])
    }

    func testClaudeInvocationDoesNotOfferUltraReasoningEffort() {
        XCTAssertFalse(AgentID.claude.allowedReasoningEfforts.contains(.ultra))
        XCTAssertTrue(AgentID.codex.allowedReasoningEfforts.contains(.ultra))
    }

    func testCodexInvocationDropsEffortUnsupportedByChosenModel() {
        let binary = URL(fileURLWithPath: "/opt/homebrew/bin/codex")
        let invocation = CodexAgent().makeIngestInvocation(
            binary: binary,
            vaultRoot: URL(fileURLWithPath: "/tmp/vault"),
            prompt: "Ingest",
            permissionMode: .codexWorkspaceWrite,
            modelName: "gpt-5.5",
            reasoningEffort: .ultra
        )

        XCTAssertFalse(invocation.contains("-c"))
        XCTAssertEqual(invocation.suffix(3), ["--model", "gpt-5.5", "Ingest"])
    }

    func testClaudeInvocationDropsEffortForModelWithoutEffortControl() {
        let binary = URL(fileURLWithPath: "/usr/local/bin/claude")
        let invocation = ClaudeCodeAgent().makeIngestInvocation(
            binary: binary,
            vaultRoot: URL(fileURLWithPath: "/tmp/vault"),
            prompt: "Ingest",
            permissionMode: .claudeAcceptEdits,
            modelName: "claude-haiku-4-5",
            reasoningEffort: .high
        )

        XCTAssertFalse(invocation.contains("--effort"))
        XCTAssertEqual(invocation.suffix(2), ["--model", "claude-haiku-4-5"])
    }

    func testCustomModelNameFallsBackToAgentWideEffortSet() {
        let binary = URL(fileURLWithPath: "/opt/homebrew/bin/codex")
        let invocation = CodexAgent().makeIngestInvocation(
            binary: binary,
            vaultRoot: URL(fileURLWithPath: "/tmp/vault"),
            prompt: "Ingest",
            permissionMode: .codexWorkspaceWrite,
            modelName: "some-unreleased-model",
            reasoningEffort: .ultra
        )

        XCTAssertEqual(invocation.suffix(5), [
            "--model",
            "some-unreleased-model",
            "-c",
            "model_reasoning_effort=\"ultra\"",
            "Ingest"
        ])
    }

    func testPiInvocationUsesEphemeralPrintModeWithModelAndThinking() {
        let invocation = PiAgent().makeIngestInvocation(
            binary: URL(fileURLWithPath: "/usr/local/bin/pi"),
            vaultRoot: URL(fileURLWithPath: "/tmp/vault"),
            prompt: "Ingest raw/source.md",
            permissionMode: .piFullAccess,
            modelName: "openai/gpt-5.4",
            reasoningEffort: .minimal
        )

        XCTAssertEqual(invocation, [
            "/usr/local/bin/pi",
            "-p",
            "--no-session",
            "--no-approve",
            "--model",
            "openai/gpt-5.4",
            "--thinking",
            "minimal",
            "Ingest raw/source.md"
        ])
    }

    func testPiInvocationProtectsPromptsFromCLIParsing() {
        for prompt in ["- ingest this", "@source.md"] {
            let invocation = PiAgent().makeIngestInvocation(
                binary: URL(fileURLWithPath: "/usr/local/bin/pi"),
                vaultRoot: URL(fileURLWithPath: "/tmp/vault"),
                prompt: prompt,
                permissionMode: .piFullAccess,
                modelName: "",
                reasoningEffort: .systemDefault
            )

            XCTAssertEqual(invocation.last, "\n\(prompt)")
        }
    }
}

final class AgentModelCatalogTests: XCTestCase {
    func testCuratedAgentsExposeModels() {
        for agent in [AgentID.claude, .codex] {
            XCTAssertFalse(agent.availableModels.isEmpty, "\(agent.displayName) has no models")
        }
    }

    func testModelIdentifiersAreUnique() {
        for agent in AgentID.allCases {
            let ids = agent.availableModels.map(\.id)
            XCTAssertEqual(ids.count, Set(ids).count, "\(agent.displayName) has duplicate model ids")
        }
    }

    func testAgentEffortSetIsUnionOfItsModels() {
        XCTAssertEqual(
            AgentID.claude.allowedReasoningEfforts,
            [.systemDefault, .low, .medium, .high, .xhigh, .max]
        )
        XCTAssertEqual(
            AgentID.codex.allowedReasoningEfforts,
            [.systemDefault, .low, .medium, .high, .xhigh, .max, .ultra]
        )
        XCTAssertEqual(
            AgentID.pi.allowedReasoningEfforts,
            [.systemDefault, .off, .minimal, .low, .medium, .high, .xhigh, .max]
        )
    }

    func testModelLookupIgnoresSurroundingWhitespace() {
        XCTAssertEqual(
            AgentModelCatalog.model(named: "  claude-opus-5 ", for: .claude)?.displayName,
            "Claude Opus 5"
        )
        XCTAssertNil(AgentModelCatalog.model(named: "claude-opus-5", for: .codex))
        XCTAssertNil(AgentModelCatalog.model(named: "", for: .claude))
    }

    #if canImport(Combine)
    @MainActor
    func testPiSettingsDefaultToSolOnHigh() {
        let defaults = UserDefaults(suiteName: "AgentModelCatalogTests-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.modelName(for: .pi), "cpa/gpt-5.6-sol")
        XCTAssertEqual(settings.reasoningEffort(for: .pi), .high)
    }

    @MainActor
    func testSelectingModelWithoutCurrentEffortResetsToSystemDefault() {
        let defaults = UserDefaults(suiteName: "AgentModelCatalogTests-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)

        settings.setModelName("gpt-5.6-sol", for: .codex)
        settings.setReasoningEffort(.ultra, for: .codex)
        XCTAssertEqual(settings.reasoningEffort(for: .codex), .ultra)

        settings.setModelName("gpt-5.5", for: .codex)
        XCTAssertEqual(settings.reasoningEffort(for: .codex), .systemDefault)
    }
    #endif

    func testModelSelectionResolvesStoredName() {
        XCTAssertEqual(ModelSelection.resolve(modelName: "", agentID: .codex), .agentDefault)
        XCTAssertEqual(
            ModelSelection.resolve(modelName: "gpt-5.6-sol", agentID: .codex),
            .known("gpt-5.6-sol")
        )
        // A codex model name selected while Claude is active is not in Claude's
        // catalog, so the picker must fall back to Custom rather than a dead tag.
        XCTAssertEqual(ModelSelection.resolve(modelName: "gpt-5.6-sol", agentID: .claude), .custom)
        XCTAssertEqual(ModelSelection.resolve(modelName: "future-model", agentID: .codex), .custom)
        XCTAssertEqual(
            ModelSelection.resolve(modelName: "", agentID: .codex, forcesCustom: true),
            .custom
        )
    }

    func testModelSelectionStoredModelName() {
        XCTAssertEqual(ModelSelection.agentDefault.storedModelName, "")
        XCTAssertEqual(ModelSelection.known("gpt-5.5").storedModelName, "gpt-5.5")
        XCTAssertNil(ModelSelection.custom.storedModelName)
    }

    func testEveryCatalogModelResolvesToAKnownSelection() {
        for agent in AgentID.allCases {
            for model in agent.availableModels {
                XCTAssertEqual(
                    ModelSelection.resolve(modelName: model.id, agentID: agent),
                    .known(model.id),
                    "\(model.id) does not round-trip through the picker"
                )
            }
        }
    }

    #if canImport(Combine)
    @MainActor
    func testEffortSetFollowsSelectedModel() {
        let defaults = UserDefaults(suiteName: "AgentModelCatalogTests-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)

        settings.setModelName("claude-haiku-4-5", for: .claude)
        XCTAssertEqual(settings.supportedReasoningEfforts(for: .claude), [.systemDefault])
        settings.setReasoningEffort(.high, for: .claude)
        XCTAssertEqual(settings.reasoningEffort(for: .claude), .systemDefault)

        settings.setModelName("claude-opus-5", for: .claude)
        settings.setReasoningEffort(.xhigh, for: .claude)
        XCTAssertEqual(settings.reasoningEffort(for: .claude), .xhigh)
    }
    #endif
}
