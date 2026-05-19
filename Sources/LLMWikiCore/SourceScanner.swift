import Foundation

public struct SourceScanner {
    public init() {}

    public func pendingSources(in paths: WikiPaths) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: paths.raw.path) else {
            return []
        }

        let resourceKeys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isHiddenKey,
            .contentModificationDateKey
        ]

        let urls = try FileManager.default.contentsOfDirectory(
            at: paths.raw,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        )

        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: resourceKeys) else { return nil }
            guard values.isRegularFile == true else { return nil }
            guard values.isHidden != true else { return nil }
            guard !FileManager.default.fileExists(atPath: paths.markerFile(for: url).path) else { return nil }
            return url
        }
        .sorted { lhs, rhs in
            let leftDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rightDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if leftDate == rightDate {
                return lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
            }
            return leftDate < rightDate
        }
    }
}
