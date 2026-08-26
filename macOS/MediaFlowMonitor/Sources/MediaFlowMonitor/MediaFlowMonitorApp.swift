import SwiftUI
import AppKit

@main
struct MediaFlowMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Fără WindowGroup vizibil — totul e gestionat de AppDelegate/OverlayWindowController.
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var metrics: SystemMetrics!
    private var logWatcher: DaVinciLogWatcher?
    private var overlayController: OverlayWindowController!
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // echivalent LSUIElement: fără icon în Dock

        // BUG FIX: fără fereastră vizibilă + fără status item, macOS marchează
        // procesul ca terminabil automat (Automatic Termination) — vezi log:
        // "_kLSApplicationWouldBeTerminatedByTALKey=1". Dezactivat explicit.
        ProcessInfo.processInfo.disableAutomaticTermination("MediaFlow Monitor overlay activ")
        ProcessInfo.processInfo.disableSuddenTermination()

        metrics = SystemMetrics()
        metrics.start()

        logWatcher = DaVinciLogWatcher()
        logWatcher?.start()

        overlayController = OverlayWindowController(metrics: metrics, logWatcher: logWatcher)

        // BUG FIX: fără NICIUN indiciu vizual la prima lansare (fără Dock icon,
        // fără fereastră), un utilizator nou credea că aplicația "nu pornește".
        // Status item permanent în bara de meniu + overlay arătat automat o dată.
        setupStatusItem()
        overlayController.toggle()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: "MediaFlow Monitor")

        let menu = NSMenu()
        menu.addItem(withTitle: "Arată/Ascunde panoul (⌘⇧M)", action: #selector(toggleOverlay), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Ieșire", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
    }

    @objc private func toggleOverlay() { overlayController.toggle() }
    @objc private func quit() { NSApp.terminate(nil) }

    func applicationWillTerminate(_ notification: Notification) {
        metrics?.stop()
        logWatcher?.stop()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
