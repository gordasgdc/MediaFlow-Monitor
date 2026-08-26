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
    private let license = LicenseManager()

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
        UpdateChecker.shared.checkAtLaunch()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: "MediaFlow Monitor")

        let menu = NSMenu()
        menu.addItem(withTitle: "Arată/Ascunde panoul (⌘⇧M)", action: #selector(toggleOverlay), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: licenseStatusText(), action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "Machine ID: \(license.machineIDDisplay)", action: #selector(copyMachineID), keyEquivalent: "")
        menu.addItem(withTitle: "Activează licența (WhatsApp)…", action: #selector(openWhatsAppActivation), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Versiune \(appVersion())", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "Caută actualizări…", action: #selector(checkForUpdates), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Ieșire", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
    }

    private func appVersion() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    private func licenseStatusText() -> String {
        switch license.state {
        case .trial(let daysLeft): return "Probă gratuită: \(daysLeft) zile rămase"
        case .trialExpired: return "Probă expirată — activare necesară"
        case .licensed(let expiresAt): return expiresAt == 0 ? "Licențiat (Lifetime)" : "Licențiat"
        }
    }

    @objc private func toggleOverlay() { overlayController.toggle() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func copyMachineID() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(license.machineIDDisplay, forType: .string)
    }

    @objc private func openWhatsAppActivation() {
        NSWorkspace.shared.open(license.whatsAppActivationURL)
    }

    @objc private func checkForUpdates() {
        UpdateChecker.shared.checkManually()
    }

    func applicationWillTerminate(_ notification: Notification) {
        metrics?.stop()
        logWatcher?.stop()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
