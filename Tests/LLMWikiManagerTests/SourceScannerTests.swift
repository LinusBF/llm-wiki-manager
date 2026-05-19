import XCTest
@testable import LLMWikiCore

final class SourceScannerTests: XCTestCase {
    func testScannerReturnsOnlyTopLevelUnmarkedFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("llm-wiki-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = WikiPaths(vaultRoot: root)
        try paths.ensureVaultDirectories()

        let sourceA = paths.raw.appendingPathComponent("a.md")
        let sourceB = paths.raw.appendingPathComponent("b.md")
        let assets = paths.raw.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        try "A".write(to: sourceA, atomically: true, encoding: .utf8)
        try "B".write(to: sourceB, atomically: true, encoding: .utf8)
        try "image".write(to: assets.appendingPathComponent("image.txt"), atomically: true, encoding: .utf8)
        try Data().write(to: paths.markerFile(for: sourceB))

        let pending = try SourceScanner().pendingSources(in: paths)

        XCTAssertEqual(pending.map(\.lastPathComponent), ["a.md"])
    }
}
