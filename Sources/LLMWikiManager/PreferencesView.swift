import AppKit
import LLMWikiCore
import SwiftUI

struct PreferencesView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var service: WikiIngestService
    @State private var showsCustomModelField = false

    var body: some View {
        TabView {
            generalTab
                .tabItem { Text("General") }
            ingestionTab
                .tabItem { Text("Ingestion") }
            notificationsTab
                .tabItem { Text("Notifications") }
            aboutTab
                .tabItem { Text("About") }
        }
        .padding(20)
        .frame(minWidth: 620, minHeight: 500)
    }

    private var generalTab: some View {
        Form {
            Section("Vault") {
                HStack {
                    TextField("Vault folder", text: $settings.vaultPath)
                    Button("Choose…") { chooseVault() }
                }
            }

            Section("Agent") {
                Picker("Active agent", selection: Binding(
                    get: { settings.activeAgentID },
                    set: { service.requestAgentSwitch(to: $0) }
                )) {
                    ForEach(AgentID.allCases) { agent in
                        Text(agent.displayName).tag(agent)
                    }
                }
                .pickerStyle(.menu)

                HStack {
                    TextField("Claude binary", text: $settings.claudeBinaryPath)
                    Button("Detect") {
                        settings.claudeBinaryPath = BinaryLocator.find("claude")?.path ?? ""
                    }
                }

                HStack {
                    TextField("Codex binary", text: $settings.codexBinaryPath)
                    Button("Detect") {
                        settings.codexBinaryPath = BinaryLocator.find("codex")?.path ?? ""
                    }
                }

                HStack {
                    TextField("Pi binary", text: $settings.piBinaryPath)
                    Button("Detect") {
                        settings.piBinaryPath = BinaryLocator.find("pi")?.path ?? ""
                    }
                }
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { enabled in
                        do {
                            try LoginItemController.setEnabled(enabled)
                            settings.launchAtLogin = enabled
                        } catch {
                            showAlert(title: "Could not update login item", message: error.localizedDescription)
                        }
                    }
                ))
            }
        }
    }

    private var ingestionTab: some View {
        Form {
            Section("Agent Options") {
                Picker("Ingest mode", selection: $settings.ingestDepth) {
                    ForEach(IngestDepth.allCases) { depth in
                        Text(depth.displayName).tag(depth)
                    }
                }
                .pickerStyle(.segmented)

                modelPicker
                effortPicker
            }

            Section("Permission Mode") {
                Picker("Mode", selection: Binding(
                    get: { settings.permissionMode(for: settings.activeAgentID) },
                    set: { service.setPermissionMode($0, for: settings.activeAgentID) }
                )) {
                    ForEach(settings.activeAgentID.allowedPermissionModes) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Prompt Template") {
                TextEditor(text: $settings.promptTemplate)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 180)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.25))
                    )
            }

            Section("Retries") {
                Stepper("Max retries: \(settings.maxRetries)", value: $settings.maxRetries, in: 1...10)
                HStack {
                    Text("Initial backoff")
                    TextField("Seconds", value: $settings.retryBackoffSeconds, formatter: NumberFormatter.decimal)
                        .frame(width: 90)
                    Text("seconds")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var modelPicker: some View {
        let agent = settings.activeAgentID

        Picker("Model", selection: Binding(
            get: { modelSelection },
            set: { applyModelSelection($0) }
        )) {
            Text("\(agent.displayName) default").tag(ModelSelection.agentDefault)
            ForEach(agent.availableModels) { model in
                Text(model.displayName).tag(ModelSelection.known(model.id))
            }
            Text("Custom…").tag(ModelSelection.custom)
        }
        .pickerStyle(.menu)
        .onChange(of: agent) { _, _ in
            showsCustomModelField = false
        }

        if isCustomModelSelected {
            TextField("Model name passed to --model", text: Binding(
                get: { settings.modelName(for: agent) },
                set: { settings.setModelName($0, for: agent) }
            ))
            .font(.system(.body, design: .monospaced))
        }

        if let model = settings.selectedModel(for: agent) {
            Text("\(model.id) · \(model.summary)")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if !isCustomModelSelected {
            Text("Lets the \(agent.displayName) CLI pick its own default model.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var effortPicker: some View {
        let agent = settings.activeAgentID
        let efforts = settings.supportedReasoningEfforts(for: agent)

        Picker("Reasoning effort", selection: Binding(
            get: { settings.reasoningEffort(for: agent) },
            set: { settings.setReasoningEffort($0, for: agent) }
        )) {
            ForEach(efforts) { effort in
                Text(effort.displayName).tag(effort)
            }
        }
        .pickerStyle(.menu)
        .disabled(efforts.count <= 1)

        if efforts.count <= 1, let model = settings.selectedModel(for: agent) {
            Text("\(model.displayName) has no reasoning effort control.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var modelSelection: ModelSelection {
        let agent = settings.activeAgentID
        return ModelSelection.resolve(
            modelName: settings.modelName(for: agent),
            agentID: agent,
            forcesCustom: showsCustomModelField
        )
    }

    private var isCustomModelSelected: Bool {
        modelSelection == .custom
    }

    private func applyModelSelection(_ selection: ModelSelection) {
        showsCustomModelField = selection == .custom
        if let name = selection.storedModelName {
            settings.setModelName(name, for: settings.activeAgentID)
        }
    }

    private var notificationsTab: some View {
        Form {
            Picker("Notify", selection: $settings.notificationMode) {
                ForEach(NotificationMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.radioGroup)
        }
    }

    private var aboutTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("LLM Wiki Manager")
                .font(.title2.weight(.semibold))
            Text("A quiet menu bar runner for ingesting new raw sources into an agent-maintained Markdown wiki.")
                .foregroundStyle(.secondary)
            Divider()
            Link("Karpathy LLM Wiki gist", destination: URL(string: "https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f")!)
            Link("Claude Code install docs", destination: URL(string: "https://docs.anthropic.com/en/docs/claude-code")!)
            Link("OpenAI Codex docs", destination: URL(string: "https://developers.openai.com/codex")!)
            Link("Pi coding agent docs", destination: URL(string: "https://github.com/earendil-works/pi/tree/main/packages/coding-agent")!)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

private extension NumberFormatter {
    static var decimal: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimum = 1
        formatter.maximum = 3600
        return formatter
    }
}
