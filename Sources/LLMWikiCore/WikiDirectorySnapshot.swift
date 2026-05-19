import Foundation

public struct WikiDirectorySnapshot: Equatable {
    public var markdownFiles: [String: Date]

    public init(markdownFiles: [String: Date]) {
        self.markdownFiles = markdownFiles
    }

    public init(wikiURL: URL) {
        var files: [String: Date] = [:]
        let manager = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]

        guard let enumerator = manager.enumerator(
            at: wikiURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            self.markdownFiles = [:]
            return
        }

        for case let url as URL in enumerator {
            guard url.pathExtension.lowercased() == "md" else { continue }
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            guard values.isRegularFile == true else { continue }
            let relativePath = String(url.path.dropFirst(wikiURL.path.count + 1))
            files[relativePath] = values.contentModificationDate ?? .distantPast
        }

        self.markdownFiles = files
    }

    public func changedFileCount(comparedTo previous: WikiDirectorySnapshot) -> Int {
        var changed = 0

        for (path, date) in markdownFiles {
            if previous.markdownFiles[path] != date {
                changed += 1
            }
        }

        for path in previous.markdownFiles.keys where markdownFiles[path] == nil {
            changed += 1
        }

        return changed
    }
}
