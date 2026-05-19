import AppKit
import LLMWikiCore
import SwiftUI

@MainActor
final class SetupWizardWindowController {
    private let window: NSWindow

    init(settings: AppSettings, service: WikiIngestService) {
        let view = SetupWizardView(settings: settings, service: service)
        let hostingController = NSHostingController(rootView: view)
        window = NSWindow(contentViewController: hostingController)
        window.title = "Set Up LLM Wiki Manager"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 640, height: 430))
        window.isReleasedWhenClosed = false
        window.center()
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

struct SetupWizardView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var service: WikiIngestService
    @State private var step = 0

    private var detectedAgents: [AgentID: URL?] {
        Dictionary(uniqueKeysWithValues: AgentID.allCases.map { ($0, settings.binaryURL(for: $0)) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            content
            Spacer()
            HStack {
                if step > 0 {
                    Button("Back") { step -= 1 }
                }
                Spacer()
                Button(step == 4 ? "Done" : "Continue") {
                    advance()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canContinue)
            }
        }
        .padding(28)
        .frame(minWidth: 640, minHeight: 430)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0:
            VStack(alignment: .leading, spacing: 12) {
                Text("Welcome")
                    .font(.largeTitle.weight(.semibold))
                Text("LLM Wiki Manager watches your vault’s `raw/` folder and runs your chosen coding agent whenever a new source appears.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Link("Read the LLM Wiki pattern", destination: URL(string: "https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f")!)
            }
        case 1:
            VStack(alignment: .leading, spacing: 14) {
                Text("Detect Agents")
                    .font(.largeTitle.weight(.semibold))
                ForEach(AgentID.allCases) { agent in
                    HStack {
                        Circle()
                            .fill(detectedAgents[agent]??.path.isEmpty == false ? Color.green : Color.gray)
                            .frame(width: 10, height: 10)
                        VStack(alignment: .leading) {
                            Text(agent.displayName)
                            Text(detectedAgents[agent]??.path ?? "Not found")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Use") {
                            settings.activeAgentID = agent
                        }
                        .disabled(detectedAgents[agent] == nil)
                    }
                }
            }
        case 2:
            VStack(alignment: .leading, spacing: 14) {
                Text("Choose Vault")
                    .font(.largeTitle.weight(.semibold))
                HStack {
                    Text(settings.vaultPath.isEmpty ? "No vault selected" : settings.vaultPath)
                        .lineLimit(2)
                    Spacer()
                    Button("Choose…") { chooseVault() }
                }
                Text("If `raw/`, `wiki/`, or `.ingested/` are missing, they will be created.")
                    .foregroundStyle(.secondary)
            }
        case 3:
            VStack(alignment: .leading, spacing: 14) {
                Text("Schema")
                    .font(.largeTitle.weight(.semibold))
                Text("Active agent: \(settings.activeAgentID.displayName)")
                Text(schemaStatus)
                    .foregroundStyle(schemaExists ? Color.secondary : Color.orange)
                Button("Create default \(settings.activeAgentID.schemaFilename)") {
                    service.createDefaultSchema()
                }
                .disabled(schemaExists)
            }
        default:
            VStack(alignment: .leading, spacing: 12) {
                Text("Ready")
                    .font(.largeTitle.weight(.semibold))
                Text("The watcher is ready. New top-level files in `raw/` will be queued for serial ingestion.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var schemaExists: Bool {
        guard let paths = service.activePaths else { return false }
        return FileManager.default.fileExists(atPath: paths.schemaFile(for: settings.activeAgentID).path)
    }

    private var schemaStatus: String {
        schemaExists
            ? "\(settings.activeAgentID.schemaFilename) exists at the vault root."
            : "\(settings.activeAgentID.schemaFilename) is missing. The app can run without it, but results will be generic."
    }

    private var canContinue: Bool {
        switch step {
        case 1:
            detectedAgents.values.contains { $0 != nil }
        case 2:
            !settings.vaultPath.isEmpty
        default:
            true
        }
    }

    private func advance() {
        if step == 1, settings.binaryURL(for: settings.activeAgentID) == nil {
            if let firstDetected = AgentID.allCases.first(where: { settings.binaryURL(for: $0) != nil }) {
                settings.activeAgentID = firstDetected
            }
        }

        if step == 4 {
            service.start()
            NSApp.keyWindow?.close()
        } else {
            step += 1
        }
    }

    private func chooseVault() {
        let panel = NSOpenPanel()
        panel.title = "Choose your LLM Wiki vault"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            service.chooseVault(url)
        }
    }
}
