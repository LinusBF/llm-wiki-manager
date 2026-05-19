import AppKit
import LLMWikiCore
import SwiftUI

@MainActor
final class PreferencesWindowController {
    private let window: NSWindow

    init(settings: AppSettings, service: WikiIngestService) {
        let view = PreferencesView(settings: settings, service: service)
        let hostingController = NSHostingController(rootView: view)
        window = NSWindow(contentViewController: hostingController)
        window.title = "LLM Wiki Manager Preferences"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 620, height: 500))
        window.isReleasedWhenClosed = false
        window.center()
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
