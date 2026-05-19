import Foundation
import LLMWikiCore

final class OutputLineBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private let maximumCount: Int
    private var lines: [ProcessOutputLine] = []

    init(maximumCount: Int = 200) {
        self.maximumCount = maximumCount
    }

    func append(_ line: ProcessOutputLine) {
        lock.lock()
        lines.append(line)
        if lines.count > maximumCount {
            lines.removeFirst(lines.count - maximumCount)
        }
        lock.unlock()
    }

    func clear() {
        lock.lock()
        lines.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    func snapshot() -> [ProcessOutputLine] {
        lock.lock()
        let snapshot = lines
        lock.unlock()
        return snapshot
    }
}
