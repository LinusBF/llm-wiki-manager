import Foundation

public enum DefaultSchema {
    public static func writeStarterSchemasIfMissing(in paths: WikiPaths) throws {
        for agentID in AgentID.allCases {
            let url = paths.schemaFile(for: agentID)
            if !FileManager.default.fileExists(atPath: url.path) {
                try contents(for: agentID).write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

    public static func contents(for agentID: AgentID) -> String {
        for bundle in templateBundles() {
            let candidateURLs = [
                bundle.url(
                    forResource: agentID.schemaFilename,
                    withExtension: nil,
                    subdirectory: "StarterSchemas"
                ),
                bundle.url(
                    forResource: agentID.schemaFilename,
                    withExtension: nil
                )
            ]

            for url in candidateURLs {
                if let url,
                   let contents = try? String(contentsOf: url, encoding: .utf8) {
                    return contents
                }
            }
        }

        return """
        # \(agentID.schemaFilename.replacingOccurrences(of: ".md", with: ""))

        This vault follows the LLM Wiki pattern. Raw sources live in `raw/`. You maintain `wiki/`. The catalog is `wiki/index.md`; the chronological log is `wiki/log.md`.

        The original pattern was described by Andrej Karpathy in `llm-wiki.md`:
        https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f

        ## Directory Contract

        - Treat `raw/` as immutable source material. Read files there, but do not edit, move, or delete them.
        - Treat `wiki/` as the maintained knowledge base. Create and edit Markdown pages there as needed.
        - Keep `wiki/index.md` as the navigation catalog. Group pages by category and include a one-line summary for each page.
        - Keep `wiki/log.md` as an append-only chronology of ingests, queries, and lint passes.
        - Use Obsidian-friendly Markdown links like `[[Page Name]]` when linking wiki pages.

        ## Ingest Workflow

        When asked to ingest a source:

        1. Read the source carefully, including nearby attachments when referenced and useful.
        2. Create or update a source summary page in `wiki/`.
        3. Update relevant entity, concept, timeline, synthesis, or comparison pages.
        4. Flag contradictions or claims that supersede older notes.
        5. Update `wiki/index.md` so the new and changed pages are discoverable.
        6. Append a dated ingest entry to `wiki/log.md` with the source filename and a short summary of what changed.

        Prefer small, well-linked pages over one giant document. Preserve uncertainty and cite source filenames whenever a claim depends on a specific source.

        ## Query Workflow

        When answering a question about the wiki, read `wiki/index.md` first, then open the most relevant pages. Answer with citations to wiki pages and source filenames. If the answer itself is valuable as durable synthesis, offer to file it back into `wiki/`.

        ## Lint Workflow

        During a lint pass, look for contradictions, stale claims, orphan pages, missing links, duplicated pages, and important concepts that deserve their own page. Update the wiki directly when the fix is clear; otherwise add findings to `wiki/log.md`.
        """
    }

    private static func templateBundles() -> [Bundle] {
        let resourceBundleName = "LLMWikiManager_LLMWikiCore.bundle"
        var bundles: [Bundle] = []

        let appBundleCandidates = [
            Bundle.main.resourceURL?.appendingPathComponent(resourceBundleName),
            Bundle.main.bundleURL.appendingPathComponent(resourceBundleName)
        ]

        for url in appBundleCandidates {
            if let url, let bundle = Bundle(url: url) {
                bundles.append(bundle)
            }
        }

        bundles.append(Bundle.module)
        return bundles
    }
}
