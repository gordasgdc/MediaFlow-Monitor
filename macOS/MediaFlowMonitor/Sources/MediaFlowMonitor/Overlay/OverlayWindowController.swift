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

        // Dashboard-ul Pro e mult mai mare decât mini-cardul inițial —
        // fereastră titled/resizable, nu mai e un mic panou colțuit.
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 760),
            styleMask: [.nonactivatingPanel, .titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        panel.title = "MediaFlow Monitor"
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = NSHostingView(
            rootView: DashboardView(metrics: metrics, logWatcher: logWatcher)
        )
        // Redimensionare liberă, cu o dimensiune minimă absolută sub care
        // fereastra NU poate fi micșorată — sub acest prag cardurile/inelele
        // s-ar suprapune peste bara de titlu (bug raportat, corectat 2026-08-26).
        panel.minSize = NSSize(width: 800, height: 650)
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
