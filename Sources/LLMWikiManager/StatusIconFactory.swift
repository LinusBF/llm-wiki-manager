import AppKit

enum StatusIconFactory {
    static func image(for state: RuntimeState, pulseOn: Bool) -> NSImage? {
        let baseName = "book.closed"
        guard let base = NSImage(systemSymbolName: baseName, accessibilityDescription: nil) else {
            return nil
        }

        let badgeName: String?
        let badgeColor: NSColor

        switch state {
        case .paused:
            badgeName = "pause.circle.fill"
            badgeColor = .controlAccentColor
        case .error:
            badgeName = "exclamationmark.triangle.fill"
            badgeColor = .systemRed
        case .setupNeeded:
            badgeName = "exclamationmark.circle.fill"
            badgeColor = .systemRed
        case .warning:
            badgeName = "exclamationmark.circle.fill"
            badgeColor = .systemYellow
        case .watching:
            badgeName = nil
            badgeColor = .labelColor
        case .ingesting:
            badgeName = pulseOn ? "circle.fill" : nil
            badgeColor = .controlAccentColor
        }

        guard let badgeName, let badge = NSImage(systemSymbolName: badgeName, accessibilityDescription: nil) else {
            base.isTemplate = true
            return base
        }

        let image = NSImage(size: NSSize(width: 24, height: 20))
        image.lockFocus()
        base.draw(in: NSRect(x: 1, y: 1, width: 18, height: 18), from: .zero, operation: .sourceOver, fraction: 1)
        badgeColor.set()
        badge.draw(
            in: NSRect(x: 12, y: 0, width: 11, height: 11),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
