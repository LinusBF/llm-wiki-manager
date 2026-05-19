import AppKit
import LLMWikiCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings()
    lazy var service = WikiIngestService(settings: settings)

    private var statusController: StatusBarController?
    private var preferencesWindowController: PreferencesWindowController?
    private var setupWizardWindowController: SetupWizardWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusController = StatusBarController(
            settings: settings,
            service: service,
            openPreferences: { [weak self] in self?.showPreferences() },
            openSetup: { [weak self] in self?.showSetupWizard() }
        )

        service.start()

        if service.needsSetup {
            showSetupWizard()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        service.terminateRunningIngest()
    }

    func showPreferences() {
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController(settings: settings, service: service)
        }

        preferencesWindowController?.show()
    }

    func showSetupWizard() {
        if setupWizardWindowController == nil {
            setupWizardWindowController = SetupWizardWindowController(settings: settings, service: service)
        }

        setupWizardWindowController?.show()
    }
}
