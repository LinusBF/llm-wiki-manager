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

    func testCodexInvocationIgnoresUnsupportedMaxReasoningEffort() {
        let binary = URL(fileURLWithPath: "/opt/homebrew/bin/codex")
        let invocation = CodexAgent().makeIngestInvocation(
            binary: binary,
            vaultRoot: URL(fileURLWithPath: "/tmp/vault"),
            prompt: "Ingest",
            permissionMode: .codexWorkspaceWrite,
            modelName: "",
            reasoningEffort: .max
        )

        XCTAssertFalse(invocation.contains("-c"))
    }
}
