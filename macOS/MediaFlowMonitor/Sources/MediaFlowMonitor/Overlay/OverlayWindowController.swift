import AppKit
import SwiftUI

/// Fereastră mică, borderless, always-on-top, deasupra DaVinci Resolve.
final class OverlayWindowController: NSWindowController {

    private var shortcut: GlobalShortcut?
    private var metrics: SystemMetrics
    private var logWatcher: DaVinciLogWatcher?

    init(metrics: SystemMetrics, logWatcher: DaVinciLogWatcher?) {
        self.metrics = metrics
        self.logWatcher = logWatcher

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 180),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = NSHostingView(
            rootView: OverlayView(metrics: metrics, logWatcher: logWatcher)
        )
        panel.center()
        panel.orderOut(nil) // pornește ascuns

        super.init(window: panel)

        shortcut = GlobalShortcut { [weak self] in self?.toggle() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    func toggle() {
        guard let window else { return }
        if window.isVisible {
            window.orderOut(nil)
        } else {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
