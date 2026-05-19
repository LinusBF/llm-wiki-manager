import AppKit
import Combine
import LLMWikiCore

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let settings: AppSettings
    private let service: WikiIngestService
    private let statusItem: NSStatusItem
    private let openPreferences: () -> Void
    private let openSetup: () -> Void
    private var cancellables = Set<AnyCancellable>()
    private var pulseTimer: Timer?
    private var pulseOn = false

    init(
        settings: AppSettings,
        service: WikiIngestService,
        openPreferences: @escaping () -> Void,
        openSetup: @escaping () -> Void
    ) {
        self.settings = settings
        self.service = service
        self.openPreferences = openPreferences
        self.openSetup = openSetup
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        service.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.refresh() }
            }
            .store(in: &cancellables)

        settings.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.refresh() }
            }
            .store(in: &cancellables)

        refresh()
    }

    private func refresh() {
        updateIcon()
        updatePulseTimer()
        rebuildMenu()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu(into: menu)
    }

    private func rebuildMenu() {
        let menu = statusItem.menu ?? NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        rebuildMenu(into: menu)
        statusItem.menu = menu
    }

    private func rebuildMenu(into menu: NSMenu) {
        menu.removeAllItems()

        let vaultName = settings.resolvedVaultURL()?.lastPathComponent ?? "No vault selected"
        menu.addDisabledItem(title: "📚 \(vaultName)")
        menu.addDisabledItem(title: "Agent: \(settings.activeAgentID.displayName)")
        menu.addDisabledItem(title: service.statusLine)
        menu.addItem(.separator())

        if service.needsSetup {
            menu.addItem(title: "Setup…", action: #selector(setup), target: self)
            menu.addItem(.separator())
        }

        let pauseTitle = service.isPaused ? "Resume" : "Pause"
        menu.addItem(title: pauseTitle, action: #selector(togglePause), target: self)
        menu.addItem(title: "Ingest now", action: #selector(ingestNow), target: self)
        menu.addItem(title: "Re-ingest file…", action: #selector(reingestFile), target: self)
        menu.addItem(.separator())

        let recentMenu = NSMenu()
        if service.recent.isEmpty {
            recentMenu.addDisabledItem(title: "No ingestions yet")
        } else {
            for item in service.recent.prefix(5) {
                let status = item.status == .failed ? "Failed" : "Ingested"
                let title = "\(status): \(item.sourceURL.lastPathComponent) · \(item.agentId.displayName)"
                recentMenu.addDisabledItem(title: title)
            }
        }
        let recentItem = NSMenuItem(title: "Recent ingestions", action: nil, keyEquivalent: "")
        recentItem.submenu = recentMenu
        menu.addItem(recentItem)

        let messagesItem = NSMenuItem(title: "Agent messages", action: nil, keyEquivalent: "")
        messagesItem.submenu = makeAgentMessagesMenu()
        menu.addItem(messagesItem)

        menu.addItem(title: "Open vault in Finder", action: #selector(openVault), target: self)
        menu.addItem(title: "Open log", action: #selector(openLog), target: self)
        menu.addItem(.separator())

        let preferences = NSMenuItem(title: "Preferences…", action: #selector(preferences), keyEquivalent: ",")
        preferences.target = self
        menu.addItem(preferences)

        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func makeAgentMessagesMenu() -> NSMenu {
        let menu = NSMenu()

        if let currentItem = service.currentItem {
            menu.addDisabledItem(title: "\(currentItem.agentId.displayName) · \(currentItem.sourceURL.lastPathComponent)")
            menu.addItem(.separator())
        }

        let lines = service.lastOutputLines.suffix(5)
        guard !lines.isEmpty else {
            menu.addDisabledItem(title: "No agent messages yet")
            return menu
        }

        for line in lines {
            let title = "[\(line.stream)] \(line.text.menuPreview)"
            menu.addDisabledItem(title: title)
        }

        return menu
    }

    private func updateIcon() {
        statusItem.button?.image = StatusIconFactory.image(for: service.runtimeState, pulseOn: pulseOn)
        statusItem.button?.toolTip = "LLM Wiki Manager: \(service.statusLine)"
    }

    private func updatePulseTimer() {
        guard case .ingesting = service.runtimeState else {
            pulseTimer?.invalidate()
            pulseTimer = nil
            pulseOn = false
            return
        }

        guard pulseTimer == nil else { return }
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pulseOn.toggle()
                self?.updateIcon()
            }
        }
    }

    @objc private func togglePause() {
        service.isPaused ? service.resume() : service.pause()
    }

    @objc private func ingestNow() {
        service.ingestNow()
    }

    @objc private func reingestFile() {
        guard let vaultURL = settings.resolvedVaultURL() else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose a raw source to re-ingest"
        panel.directoryURL = vaultURL.appendingPathComponent("raw", isDirectory: true)
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            service.reingest(fileURL: url)
        }
    }

    @objc private func openVault() {
        guard let vaultURL = settings.resolvedVaultURL() else { return }
        NSWorkspace.shared.activateFileViewerSelecting([vaultURL])
    }

    @objc private func openLog() {
        guard let paths = service.activePaths else { return }
        if !FileManager.default.fileExists(atPath: paths.appLog.path) {
            try? Data().write(to: paths.appLog)
        }
        NSWorkspace.shared.open(paths.appLog)
    }

    @objc private func preferences() {
        openPreferences()
    }

    @objc private func setup() {
        openSetup()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

private extension NSMenu {
    func addDisabledItem(title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        addItem(item)
    }

    @discardableResult
    func addItem(title: String, action: Selector?, target: AnyObject?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target
        addItem(item)
        return item
    }
}

private extension String {
    var menuPreview: String {
        let flattened = replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard flattened.count > 100 else { return flattened }
        return "\(flattened.prefix(97))..."
    }
}
