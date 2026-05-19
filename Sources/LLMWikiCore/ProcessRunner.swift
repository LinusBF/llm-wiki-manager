import Foundation

public struct ProcessOutputLine: Equatable, Sendable {
    public var timestamp: Date
    public var stream: String
    public var text: String

    public init(timestamp: Date = Date(), stream: String, text: String) {
        self.timestamp = timestamp
        self.stream = stream
        self.text = text
    }
}

public struct ProcessRunResult: Equatable, Sendable {
    public var exitCode: Int32
    public var durationSeconds: Double

    public init(exitCode: Int32, durationSeconds: Double) {
        self.exitCode = exitCode
        self.durationSeconds = durationSeconds
    }
}

public enum ProcessRunnerError: LocalizedError {
    case emptyInvocation
    case executableMissing(String)

    public var errorDescription: String? {
        switch self {
        case .emptyInvocation:
            "The agent invocation was empty."
        case let .executableMissing(path):
            "The executable does not exist or is not executable: \(path)"
        }
    }
}

public final class ProcessRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var runningProcess: Process?

    public init() {}

    public func terminateRunningProcess() {
        lock.lock()
        let process = runningProcess
        lock.unlock()
        process?.terminate()
    }

    public func run(
        invocation: [String],
        currentDirectory: URL,
        lineHandler: @escaping (ProcessOutputLine) -> Void
    ) async throws -> ProcessRunResult {
        guard let executable = invocation.first else {
            throw ProcessRunnerError.emptyInvocation
        }

        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw ProcessRunnerError.executableMissing(executable)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = Array(invocation.dropFirst())
        process.currentDirectoryURL = currentDirectory
        process.environment = ProcessInfo.processInfo.environment

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let stdoutPump = LinePump(stream: "stdout", lineHandler: lineHandler)
        let stderrPump = LinePump(stream: "stderr", lineHandler: lineHandler)

        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                stdoutPump.flush()
                handle.readabilityHandler = nil
            } else {
                stdoutPump.append(data)
            }
        }

        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                stderrPump.flush()
                handle.readabilityHandler = nil
            } else {
                stderrPump.append(data)
            }
        }

        let startedAt = Date()

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { [weak self] finishedProcess in
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                stdoutPump.flush()
                stderrPump.flush()

                self?.lock.lock()
                if self?.runningProcess === finishedProcess {
                    self?.runningProcess = nil
                }
                self?.lock.unlock()

                continuation.resume(
                    returning: ProcessRunResult(
                        exitCode: finishedProcess.terminationStatus,
                        durationSeconds: Date().timeIntervalSince(startedAt)
                    )
                )
            }

            do {
                lock.lock()
                runningProcess = process
                lock.unlock()
                try process.run()
            } catch {
                lock.lock()
                if runningProcess === process {
                    runningProcess = nil
                }
                lock.unlock()
                continuation.resume(throwing: error)
            }
        }
    }
}

private final class LinePump {
    private let stream: String
    private let lineHandler: (ProcessOutputLine) -> Void
    private let queue = DispatchQueue(label: "app.llm-wiki.line-pump")
    private var buffer = Data()

    init(stream: String, lineHandler: @escaping (ProcessOutputLine) -> Void) {
        self.stream = stream
        self.lineHandler = lineHandler
    }

    func append(_ data: Data) {
        queue.async {
            self.buffer.append(data)
            self.emitCompleteLines()
        }
    }

    func flush() {
        queue.sync {
            guard !buffer.isEmpty else { return }
            let text = String(decoding: buffer, as: UTF8.self)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\r\n"))
            buffer.removeAll(keepingCapacity: true)
            if !text.isEmpty {
                lineHandler(ProcessOutputLine(stream: stream, text: text))
            }
        }
    }

    private func emitCompleteLines() {
        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[..<newlineIndex]
            buffer.removeSubrange(...newlineIndex)
            var text = String(decoding: lineData, as: UTF8.self)
            if text.last == "\r" {
                text.removeLast()
            }
            if !text.isEmpty {
                lineHandler(ProcessOutputLine(stream: stream, text: text))
            }
        }
    }
}
