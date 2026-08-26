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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // echivalent LSUIElement: fără icon în Dock

        metrics = SystemMetrics()
        metrics.start()

        logWatcher = DaVinciLogWatcher()
        logWatcher?.start()

        overlayController = OverlayWindowController(metrics: metrics, logWatcher: logWatcher)
    }

    func applicationWillTerminate(_ notification: Notification) {
        metrics?.stop()
        logWatcher?.stop()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
