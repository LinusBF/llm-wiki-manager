import AppKit
import Combine
import LLMWikiCore
import UserNotifications

enum RuntimeState: Equatable {
    case setupNeeded
    case watching
    case ingesting
    case paused
    case error(String)
    case warning(String)
}

@MainActor
final class WikiIngestService: ObservableObject {
    @Published private(set) var runtimeState: RuntimeState = .setupNeeded
    @Published private(set) var statusLine = "Setup needed"
    @Published private(set) var queue: [QueueItem] = []
    @Published private(set) var recent: [QueueItem] = []
    @Published private(set) var currentItem: QueueItem?
    @Published private(set) var isPaused = false

    let settings: AppSettings

    private let watcher = RawFolderWatcher()
    private let scanner = SourceScanner()
    private let runner = ProcessRunner()
    private let outputBuffer = OutputLineBuffer()
    private var logger: OperationalLogger?
    private var isProcessing = false
    private var retryTask: Task<Void, Never>?
    private var pendingAgentSwitch: AgentID?
    private var watcherSuspendedForSwitch = false
    private var cancellables = Set<AnyCancellable>()

    init(settings: AppSettings) {
        self.settings = settings
        settings.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in self?.refreshStatus() }
            }
            .store(in: &cancellables)
    }

    var needsSetup: Bool {
        settings.resolvedVaultURL() == nil || !hasAnyAgentInstalled
    }

    var pendingCount: Int {
        queue.filter { $0.status == .pending || $0.status == .retrying }.count
    }

    var failedCount: Int {
        queue.filter { $0.status == .failed }.count
    }

    var activePaths: WikiPaths? {
        settings.resolvedVaultURL().map(WikiPaths.init(vaultRoot:))
    }

    var hasAnyAgentInstalled: Bool {
        AgentID.allCases.contains { settings.binaryURL(for: $0) != nil }
    }

    var lastOutputLines: [ProcessOutputLine] {
        outputBuffer.snapshot()
    }

    func start() {
        guard let paths = activePaths else {
            runtimeState = .setupNeeded
            statusLine = "Pick a vault folder to start watching"
            return
        }

        do {
            try paths.ensureVaultDirectories()
            try paths.ensurePromptFile(defaultPrompt: settings.promptTemplate)
            logger = OperationalLogger(fileURL: paths.appLog)
            loadPersistedState(from: paths)
            startWatcher(paths: paths)
            rescanAndEnqueue()
            refreshStatus()
            processNextIfPossible()
        } catch {
            runtimeState = .error(error.localizedDescription)
            statusLine = error.localizedDescription
        }
    }

    func pause() {
        isPaused = true
        if !isProcessing {
            runtimeState = .paused
        }
        refreshStatus()
    }

    func resume() {
        isPaused = false
        runtimeState = .watching
        rescanAndEnqueue()
        processNextIfPossible()
        refreshStatus()
    }

    func ingestNow() {
        if isPaused {
            resume()
        } else {
            rescanAndEnqueue()
            processNextIfPossible()
        }
    }

    func terminateRunningIngest() {
        runner.terminateRunningProcess()
    }

    func reingest(fileURL: URL) {
        guard let paths = activePaths else { return }

        try? FileManager.default.removeItem(at: paths.markerFile(for: fileURL))
        queue.removeAll { $0.filePath == fileURL.path }
        queue.append(QueueItem(filePath: fileURL.path, agentId: settings.activeAgentID))
        persistState()
        processNextIfPossible()
        refreshStatus()
    }

    func requestAgentSwitch(to newAgentID: AgentID) {
        guard newAgentID != settings.activeAgentID else { return }

        guard settings.binaryURL(for: newAgentID) != nil else {
            showAlert(
                title: "\(newAgentID.displayName) CLI not found",
                message: "Configure the binary path in Preferences before switching."
            )
            refreshStatus()
            return
        }

        if isProcessing {
            pendingAgentSwitch = newAgentID
            watcher.stop()
            watcherSuspendedForSwitch = true
            refreshStatus()
            return
        }

        performAgentSwitch(to: newAgentID)
    }

    func setPermissionMode(_ mode: PermissionMode, for agentID: AgentID) {
        guard agentID.allowedPermissionModes.contains(mode) else { return }

        if mode.isDangerous {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Enable \(mode.displayName)?"
            alert.informativeText = "This gives the agent broader access than the default ingest mode. Only use it for vaults and sources you trust."
            alert.addButton(withTitle: "Enable")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else {
                objectWillChange.send()
                return
            }
        }

        settings.setPermissionMode(mode, for: agentID)
    }

    func createDefaultSchema(for agentID: AgentID? = nil) {
        guard let paths = activePaths else { return }
        let id = agentID ?? settings.activeAgentID
        let url = paths.schemaFile(for: id)
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try DefaultSchema.contents(for: id).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            showAlert(title: "Could not create \(id.schemaFilename)", message: error.localizedDescription)
        }
        refreshStatus()
    }

    func chooseVault(_ url: URL) {
        do {
            let shouldSeedStarterSchemas = isNewVault(url)
            try settings.setVaultURL(url)
            let paths = WikiPaths(vaultRoot: url)
            try paths.ensureVaultDirectories()
            if shouldSeedStarterSchemas {
                try DefaultSchema.writeStarterSchemasIfMissing(in: paths)
            }
            start()
        } catch {
            showAlert(title: "Could not use that vault", message: error.localizedDescription)
        }
    }

    private func startWatcher(paths: WikiPaths) {
        do {
            try watcher.start(watching: paths.raw) { [weak self] in
                Task { @MainActor in
                    self?.rescanAndEnqueue()
                    self?.processNextIfPossible()
                }
            }
        } catch {
            runtimeState = .error(error.localizedDescription)
        }
    }

    private func isNewVault(_ url: URL) -> Bool {
        let paths = WikiPaths(vaultRoot: url)
        let manager = FileManager.default
        let expectedPaths = [
            paths.raw.path,
            paths.wiki.path,
            paths.ingested.path,
            paths.schemaFile(for: .claude).path,
            paths.schemaFile(for: .codex).path
        ]
        return expectedPaths.allSatisfy { !manager.fileExists(atPath: $0) }
    }

    private func rescanAndEnqueue() {
        guard let paths = activePaths else { return }

        do {
            let existing = Set(queue.map(\.filePath))
            let pendingSources = try scanner.pendingSources(in: paths)
            let newItems = pendingSources
                .filter { !existing.contains($0.path) }
                .map { QueueItem(filePath: $0.path, agentId: settings.activeAgentID) }

            if !newItems.isEmpty {
                queue.append(contentsOf: newItems)
                persistState()
            }
        } catch {
            runtimeState = .error(error.localizedDescription)
        }

        refreshStatus()
    }

    private func processNextIfPossible() {
        guard !isProcessing else { return }
        guard !isPaused else {
            runtimeState = .paused
            refreshStatus()
            return
        }

        guard let paths = activePaths else {
            runtimeState = .setupNeeded
            refreshStatus()
            return
        }

        let now = Date()
        guard let index = queue.firstIndex(where: { item in
            switch item.status {
            case .pending:
                return true
            case .retrying:
                return (item.nextRunAt ?? .distantPast) <= now
            case .running, .failed, .succeeded:
                return false
            }
        }) else {
            scheduleNextRetryIfNeeded()
            refreshStatus()
            return
        }

        var item = queue[index]
        guard let binary = settings.binaryURL(for: item.agentId) else {
            item.status = .failed
            item.lastError = "\(item.agentId.displayName) CLI not found"
            item.finishedAt = Date()
            queue[index] = item
            recent.insert(item, at: 0)
            trimRecent()
            persistState()
            refreshStatus()
            return
        }

        let mode = settings.permissionMode(for: item.agentId)
        let modelName = settings.modelName(for: item.agentId)
        let reasoningEffort = settings.reasoningEffort(for: item.agentId)
        let ingestDepth = settings.ingestDepth
        let prompt = renderedPrompt(for: item.sourceURL, paths: paths)
        let invocation = item.agentId.adapter.makeIngestInvocation(
            binary: binary,
            vaultRoot: paths.vaultRoot,
            prompt: prompt,
            permissionMode: mode,
            modelName: modelName,
            reasoningEffort: reasoningEffort
        )

        item.status = .running
        item.attempts += 1
        let startedAt = Date()
        item.startedAt = startedAt
        item.queuedDurationSeconds = startedAt.timeIntervalSince(item.createdAt)
        item.modelName = modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : modelName
        item.reasoningEffort = reasoningEffort
        item.ingestDepth = ingestDepth
        item.lastError = nil
        queue[index] = item
        currentItem = item
        isProcessing = true
        runtimeState = .ingesting
        outputBuffer.clear()
        persistState()
        refreshStatus()

        let logger = logger
        let runner = runner
        let outputBuffer = outputBuffer
        let itemID = item.id
        let agentID = item.agentId
        let relativeFile = paths.relativePath(for: item.sourceURL)
        let vaultRoot = paths.vaultRoot
        let wikiURL = paths.wiki

        Task { [weak self] in
            let outcome = await Task.detached(priority: .utility) {
                let beforeSnapshot = WikiDirectorySnapshot(wikiURL: wikiURL)
                let result: Result<ProcessRunResult, Error>
                do {
                    let runResult = try await runner.run(
                        invocation: invocation,
                        currentDirectory: vaultRoot
                    ) { line in
                        outputBuffer.append(line)
                        Task {
                            await logger?.append(
                                OperationalLogRecord(
                                    timestamp: line.timestamp,
                                    agentId: agentID,
                                    file: relativeFile,
                                    stream: line.stream,
                                    message: line.text
                                )
                            )
                        }
                    }
                    result = .success(runResult)
                } catch {
                    result = .failure(error)
                }

                let wikiPagesUpdated: Int?
                if case let .success(runResult) = result, runResult.exitCode == 0 {
                    wikiPagesUpdated = WikiDirectorySnapshot(wikiURL: wikiURL)
                        .changedFileCount(comparedTo: beforeSnapshot)
                } else {
                    wikiPagesUpdated = nil
                }

                return (result, wikiPagesUpdated)
            }.value

            self?.finish(
                itemID: itemID,
                result: outcome.0,
                paths: paths,
                wikiPagesUpdated: outcome.1
            )
        }
    }

    private func finish(
        itemID: UUID,
        result: Result<ProcessRunResult, Error>,
        paths: WikiPaths,
        wikiPagesUpdated: Int?
    ) {
        guard let index = queue.firstIndex(where: { $0.id == itemID }) else {
            isProcessing = false
            currentItem = nil
            processNextAfterFinish()
            return
        }

        var item = queue[index]
        item.finishedAt = Date()

        switch result {
        case let .success(runResult) where runResult.exitCode == 0:
            item.status = .succeeded
            item.durationSeconds = runResult.durationSeconds
            item.wikiPagesUpdated = wikiPagesUpdated
            do {
                try Data().write(to: paths.markerFile(for: item.sourceURL), options: .atomic)
                queue.remove(at: index)
                recent.insert(item, at: 0)
                trimRecent()
                notifySuccess(item)
            } catch {
                item.status = .failed
                item.lastError = "Ingest succeeded, but marker write failed: \(error.localizedDescription)"
                queue[index] = item
                recent.insert(item, at: 0)
                trimRecent()
                notifyFailure(item)
            }

        case let .success(runResult):
            item.lastError = "Agent exited with code \(runResult.exitCode)"
            handleFailedAttempt(item: item, index: index)

        case let .failure(error):
            item.lastError = error.localizedDescription
            handleFailedAttempt(item: item, index: index)
        }

        isProcessing = false
        currentItem = nil
        persistState()
        processNextAfterFinish()
    }

    private func handleFailedAttempt(item failedItem: QueueItem, index: Int) {
        var item = failedItem
        if item.attempts < settings.maxRetries {
            item.status = .retrying
            item.nextRunAt = Date().addingTimeInterval(backoffSeconds(forAttempt: item.attempts))
            queue[index] = item
            scheduleNextRetryIfNeeded()
        } else {
            item.status = .failed
            item.nextRunAt = nil
            queue[index] = item
            recent.insert(item, at: 0)
            trimRecent()
            notifyFailure(item)
        }
    }

    private func processNextAfterFinish() {
        if let pendingAgentSwitch {
            self.pendingAgentSwitch = nil
            performAgentSwitch(to: pendingAgentSwitch)
            return
        }

        if isPaused {
            runtimeState = .paused
            refreshStatus()
            return
        }

        processNextIfPossible()
    }

    private func performAgentSwitch(to newAgentID: AgentID) {
        settings.activeAgentID = newAgentID
        if let paths = activePaths {
            let schema = paths.schemaFile(for: newAgentID)
            if !FileManager.default.fileExists(atPath: schema.path) {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = "\(newAgentID.schemaFilename) is missing"
                alert.informativeText = "The app can keep watching, but ingests work best when the active agent has a schema file at the vault root."
                alert.addButton(withTitle: "Create Default")
                alert.addButton(withTitle: "Later")
                if alert.runModal() == .alertFirstButtonReturn {
                    createDefaultSchema(for: newAgentID)
                }
            }

            if watcherSuspendedForSwitch {
                watcherSuspendedForSwitch = false
                startWatcher(paths: paths)
            }
        }

        rescanAndEnqueue()
        processNextIfPossible()
        refreshStatus()
    }

    private func renderedPrompt(for fileURL: URL, paths: WikiPaths) -> String {
        let prompt: String
        if let data = try? Data(contentsOf: paths.ingestPrompt),
           let filePrompt = String(data: data, encoding: .utf8),
           !filePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            prompt = filePrompt
        } else {
            prompt = settings.promptTemplate
        }

        let renderedPrompt = prompt.replacingOccurrences(of: "{file}", with: paths.relativePath(for: fileURL))
        return """
        \(renderedPrompt)

        \(settings.ingestDepth.promptDirective)
        """
    }

    private func loadPersistedState(from paths: WikiPaths) {
        do {
            let state = try IngestStateStore.load(from: paths.state)
            queue = state.queue.map { item in
                var updated = item
                if updated.status == .running {
                    updated.status = .pending
                    updated.startedAt = nil
                }
                return updated
            }
            recent = state.recent
        } catch {
            queue = []
            recent = []
        }
    }

    private func persistState() {
        guard let paths = activePaths else { return }
        let state = PersistedIngestState(
            queue: queue.filter { $0.status != .succeeded },
            recent: Array(recent.prefix(20))
        )
        try? IngestStateStore.save(state, to: paths.state)
    }

    private func trimRecent() {
        recent = Array(recent.prefix(20))
    }

    private func backoffSeconds(forAttempt attempt: Int) -> Double {
        switch attempt {
        case 0, 1: settings.retryBackoffSeconds
        case 2: settings.retryBackoffSeconds * 6
        default: settings.retryBackoffSeconds * 30
        }
    }

    private func scheduleNextRetryIfNeeded() {
        retryTask?.cancel()

        let nextDate = queue
            .filter { $0.status == .retrying }
            .compactMap(\.nextRunAt)
            .min()

        guard let nextDate else { return }
        let delay = max(0, nextDate.timeIntervalSinceNow)
        retryTask = Task { [weak self] in
            let nanoseconds = UInt64(delay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            await MainActor.run {
                self?.processNextIfPossible()
            }
        }
    }

    private func refreshStatus() {
        guard let paths = activePaths else {
            runtimeState = .setupNeeded
            statusLine = "Pick a vault folder to start watching"
            objectWillChange.send()
            return
        }

        if !FileManager.default.fileExists(atPath: paths.vaultRoot.path) {
            runtimeState = .error("Vault folder not found")
            statusLine = "Vault folder not found"
            objectWillChange.send()
            return
        }

        let agent = settings.activeAgentID
        let schemaExists = FileManager.default.fileExists(atPath: paths.schemaFile(for: agent).path)

        if let pendingAgentSwitch {
            statusLine = "Switching to \(pendingAgentSwitch.displayName) after current ingest"
        } else if isProcessing, let currentItem {
            statusLine = "Ingesting \(currentItem.sourceURL.lastPathComponent) with \(currentItem.agentId.displayName) · \(pendingCount) pending"
        } else if isPaused {
            runtimeState = .paused
            statusLine = "Paused · \(pendingCount) pending"
        } else if failedCount > 0 {
            runtimeState = .error("Last ingest failed")
            statusLine = "Last ingest failed · \(failedCount) failed"
        } else if settings.binaryURL(for: agent) == nil {
            runtimeState = .error("\(agent.displayName) CLI not found")
            statusLine = "\(agent.displayName) CLI not found"
        } else if !schemaExists {
            runtimeState = .warning("\(agent.schemaFilename) missing")
            statusLine = "Watching · \(pendingCount) pending · \(agent.schemaFilename) missing"
        } else if isProcessing {
            runtimeState = .ingesting
        } else {
            runtimeState = .watching
            statusLine = "Watching · \(pendingCount) pending"
        }

        objectWillChange.send()
    }

    private func notifySuccess(_ item: QueueItem) {
        guard settings.notificationMode == .everyIngest else { return }
        let pages = item.wikiPagesUpdated.map { " · \($0) wiki pages updated" } ?? ""
        let duration = item.durationSeconds.map { String(format: " · %.1fs", $0) } ?? ""
        NotificationManager.deliver(
            title: "Ingested \(item.sourceURL.lastPathComponent)",
            body: "with \(item.agentId.displayName)\(duration)\(pages)"
        )
    }

    private func notifyFailure(_ item: QueueItem) {
        guard settings.notificationMode != .never else { return }
        NotificationManager.deliver(
            title: "Ingest failed: \(item.sourceURL.lastPathComponent)",
            body: item.lastError ?? "\(item.agentId.displayName) returned an error"
        )
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
