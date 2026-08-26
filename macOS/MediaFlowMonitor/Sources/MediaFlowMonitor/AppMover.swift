import AppKit

/// Verifică dacă aplicația rulează din afara `/Applications` (ex. direct din
/// Downloads/dintr-un .zip dezarhivat) și oferă un prompt nativ de mutare —
/// echivalentul funcțional al PFMoveToApplicationsFolder/LetMove, scris fără
/// dependință externă (nu există SPM package oficial întreținut pentru asta).
enum AppMover {

    /// Apelat o singură dată, la lansare, înainte de orice altă inițializare vizuală.
    static func promptIfNeeded() {
        guard !isInApplicationsFolder() else { return }
        guard !isRunningFromXcodeOrTests() else { return }

        let alert = NSAlert()
        alert.messageText = "Mutare în Aplicații?"
        alert.informativeText = "MediaFlow Monitor rulează în afara folderului Aplicații. Pentru stabilitate (actualizări automate, permisiuni corecte), se recomandă mutarea în /Applications."
        alert.addButton(withTitle: "Mută în Aplicații")
        alert.addButton(withTitle: "Nu acum")
        alert.alertStyle = .informational

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        move()
    }

    private static func isInApplicationsFolder() -> Bool {
        let path = Bundle.main.bundlePath
        let userApps = ("~/Applications" as NSString).expandingTildeInPath
        return path.hasPrefix("/Applications/") || path.hasPrefix(userApps)
    }

    private static func isRunningFromXcodeOrTests() -> Bool {
        let path = Bundle.main.bundlePath
        return path.contains("/DerivedData/") || path.contains("/.build/") || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private static func move() {
        let fm = FileManager.default
        let source = URL(fileURLWithPath: Bundle.main.bundlePath)
        let destinationDir = URL(fileURLWithPath: "/Applications")
        let destination = destinationDir.appendingPathComponent(source.lastPathComponent)

        do {
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.copyItem(at: source, to: destination)

            // Relansează din noua locație, apoi închide instanța curentă.
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = [destination.path]
            try task.run()

            try? fm.trashItem(at: source, resultingItemURL: nil)
            NSApp.terminate(nil)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Mutare eșuată"
            alert.informativeText = "Nu am putut muta aplicația automat (\(error.localizedDescription)). Mut-o manual în /Applications din Finder."
            alert.alertStyle = .warning
            alert.runModal()
        }
    }
}
