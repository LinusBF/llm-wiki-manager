import XCTest
@testable import LLMWikiCore

final class DefaultSchemaTests: XCTestCase {
    func testStarterSchemasComeFromBundledTemplates() {
        let agents = DefaultSchema.contents(for: .codex)
        let claude = DefaultSchema.contents(for: .claude)

        XCTAssertTrue(agents.contains("AGENTS.md          # this file"))
        XCTAssertTrue(claude.contains("CLAUDE.md          # this file"))
        XCTAssertTrue(agents.contains("LLM Wiki — Schema and Conventions"))
        XCTAssertTrue(claude.contains("LLM Wiki — Schema and Conventions"))
    }

    func testWriteStarterSchemasDoesNotOverwriteExistingFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("llm-wiki-schema-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = WikiPaths(vaultRoot: root)
        try paths.ensureVaultDirectories()

        let existing = paths.schemaFile(for: .codex)
        try "custom".write(to: existing, atomically: true, encoding: .utf8)

        try DefaultSchema.writeStarterSchemasIfMissing(in: paths)

        XCTAssertEqual(try String(contentsOf: existing, encoding: .utf8), "custom")
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.schemaFile(for: .claude).path))
    }
}
