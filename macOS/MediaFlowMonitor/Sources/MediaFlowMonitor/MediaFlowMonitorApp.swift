import SwiftUI
import AppKit

@main
struct MediaFlowMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Fără WindowGroup vizibil — totul e gestionat de AppDelegate/OverlayWindowController.
        Settings { EmptyView() }
            .commands {
                // Meniul nativ de sus (vizibil cât timp aplicația e activă,
                // ex. când Dashboard-ul e deschis) — About în meniul de
                // aplicație, Ghidul de utilizare în meniul Help, ca orice
                // aplicație macOS standard.
                CommandGroup(replacing: .appInfo) {
                    Button("Despre MediaFlow Monitor") {
                        (NSApp.delegate as? AppDelegate)?.showAbout()
                    }
                }
                CommandGroup(replacing: .help) {
                    Button("Ghid de utilizare (User Manual)") {
                        (NSApp.delegate as? AppDelegate)?.showUserGuide()
                    }
                }
            }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var metrics: SystemMetrics!
    private var logWatcher: DaVinciLogWatcher?
    private var overlayController: OverlayWindowController!
    private var statusItem: NSStatusItem!
    private var licenseStatusMenuItem: NSMenuItem?
    private let license = LicenseManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // echivalent LSUIElement: fără icon în Dock

        // Bypass App Translocation: dacă rulează din Downloads/.zip extras,
        // propune mutarea în /Applications înainte de orice altă inițializare.
        AppMover.promptIfNeeded()

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
        let statusMenuItem = NSMenuItem(title: licenseStatusText(), action: nil, keyEquivalent: "")
        menu.addItem(statusMenuItem)
        licenseStatusMenuItem = statusMenuItem
        menu.addItem(withTitle: "Machine ID: \(license.machineIDDisplay)", action: #selector(copyMachineID), keyEquivalent: "")
        menu.addItem(withTitle: "Activează licența (WhatsApp)…", action: #selector(openWhatsAppActivation), keyEquivalent: "")
        menu.addItem(withTitle: "Introdu codul de activare…", action: #selector(promptActivationCode), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Ghid de utilizare (Help)…", action: #selector(showUserGuideMenuAction), keyEquivalent: "")
        menu.addItem(withTitle: "Despre MediaFlow Monitor…", action: #selector(showAboutMenuAction), keyEquivalent: "")
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

    /// BUG REAL găsit 2026-08-26: `LicenseManager.activate(serial:)` exista
    /// de la v1.0 dar nu era apelat NICĂIERI din UI — un client care plătea
    /// și primea codul pe WhatsApp nu avea cum să-l introducă în aplicație.
    @objc private func promptActivationCode() {
        let alert = NSAlert()
        alert.messageText = "Introdu codul de activare"
        alert.informativeText = "Codul primit pe WhatsApp după donație (format Base32, ex. „ABCD-EFGH-…”)."
        alert.addButton(withTitle: "Activează")
        alert.addButton(withTitle: "Anulează")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.placeholderString = "Cod de activare"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let serial = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !serial.isEmpty else { return }

        switch license.activate(serial: serial) {
        case .success:
            licenseStatusMenuItem?.title = licenseStatusText()
            let confirm = NSAlert()
            confirm.messageText = "Activare reușită"
            confirm.informativeText = "Licența a fost activată cu succes. Mulțumim pentru susținere!"
            confirm.runModal()
        case .failure(let error):
            let failAlert = NSAlert()
            failAlert.alertStyle = .warning
            failAlert.messageText = "Activare eșuată"
            failAlert.informativeText = activationErrorText(error)
            failAlert.runModal()
        }
    }

    private func activationErrorText(_ error: LicenseCore.ValidationError) -> String {
        switch error {
        case .malformedCode: return "Codul introdus nu e valid (format greșit)."
        case .badSignature: return "Codul nu a putut fi verificat (semnătură invalidă)."
        case .wrongProduct: return "Acest cod e pentru altă aplicație."
        case .wrongMachine: return "Acest cod e blocat pe alt calculator. Trimite Machine ID-ul curent pentru un cod nou."
        case .expired: return "Codul a expirat."
        }
    }

    @objc private func checkForUpdates() {
        UpdateChecker.shared.checkManually()
    }

    @objc private func showUserGuideMenuAction() { showUserGuide() }
    @objc private func showAboutMenuAction() { showAbout() }

    /// Apelat și din meniul nativ de sus (App menu → Despre), vezi
    /// `MediaFlowMonitorApp.commands`.
    func showAbout() {
        AuxWindowPresenter.present(
            id: "about", title: "Despre MediaFlow Monitor", size: NSSize(width: 340, height: 400)
        ) {
            AboutView(license: self.license)
        }
    }

    /// Apelat și din meniul nativ de sus (Help → Ghid de utilizare).
    func showUserGuide() {
        AuxWindowPresenter.present(
            id: "userGuide", title: "Ghid de utilizare — MediaFlow Monitor", size: NSSize(width: 620, height: 560)
        ) {
            UserGuideView()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        metrics?.stop()
        logWatcher?.stop()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
