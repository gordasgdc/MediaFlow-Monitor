import AppKit
import Darwin

/// Verifică dacă aplicația rulează din afara `/Applications` (ex. direct din
/// Downloads/dintr-un .zip dezarhivat) și oferă un prompt nativ de mutare —
/// echivalentul funcțional al PFMoveToApplicationsFolder/LetMove, scris fără
/// dependință externă (nu există SPM package oficial întreținut pentru asta).
///
/// App Translocation (Regula 40, verificat empiric pe macOS 26 în GDC
/// Firewall): o aplicație cu bitul 0x0080 în `com.apple.quarantine` (pus de
/// browser: `0083`, `0081`) rulează dintr-o copie izolată doar-citire, ORIUNDE
/// s-ar afla — și după o copiere cu FileManager, și după o mutare prin Finder.
/// Varianta veche compara doar calea procesului: copia din `/Applications`
/// pornea tot izolată, cerea mutarea din nou, iar a doua mutare copia
/// aplicația peste ea însăși și o ducea la Coș. Acum copia instalată primește
/// atributul fără bitul de izolare (carantina rămâne, Gatekeeper o verifică în
/// continuare), iar locația se judecă după original, nu după copia izolată.
enum AppMover {
    private static let log = DiagnosticLog("appmover")
    static let destination = URL(fileURLWithPath: "/Applications/MediaFlowMonitor.app")
    private static let quarantineKey = "com.apple.quarantine"
    private static let translocateFlag: UInt32 = 0x0080

    /// Apelat o singură dată, la lansare, înainte de orice altă inițializare vizuală.
    static func promptIfNeeded() {
        let running = Bundle.main.bundleURL
        guard !isRunningFromXcodeOrTests(running) else { return }
        let original = originalLocation(of: running)
        let translocated = original.standardizedFileURL != running.standardizedFileURL

        if isInApplicationsFolder(original) {
            guard translocated else { return }
            log.warning("Rulează izolată (App Translocation) din \(original.path) — repar pe loc")
            repairInPlace(original)
            return
        }
        log.info("Pornită din afara /Applications: \(original.path)" + (translocated ? " (App Translocation)" : ""))
        guard askToMove() else {
            log.info("Mutarea a fost refuzată")
            return
        }
        move(from: running, original: original)
    }

    // MARK: - Pași

    private static func askToMove() -> Bool {
        let wasAccessory = bringToFront()
        let alert = NSAlert()
        alert.messageText = "Mutare în Aplicații?"
        alert.informativeText = "MediaFlow Monitor rulează în afara folderului Aplicații. Pentru stabilitate (actualizări automate, permisiuni corecte), se recomandă mutarea în /Applications."
        alert.addButton(withTitle: "Mută în Aplicații")
        alert.addButton(withTitle: "Nu acum")
        alert.alertStyle = .informational
        alert.window.level = .floating
        let accepted = alert.runModal() == .alertFirstButtonReturn
        if wasAccessory, !accepted { NSApp.setActivationPolicy(.accessory) }
        return accepted
    }

    private static func move(from source: URL, original: URL) {
        do {
            terminateOtherInstances()
            // Carantina originalului e cea văzută de Gatekeeper la pornire (plus
            // aprobarea utilizatorului); copia izolată e doar o oglindă a lui.
            let quarantine = quarantineWithoutTranslocation(at: original) ?? quarantineWithoutTranslocation(at: source)
            try install(source, quarantine: quarantine)
            let installed = version(of: destination)
            guard installed == version(of: Bundle.main.bundleURL) else {
                throw failure("copia din /Applications are versiunea \(installed ?? "?")")
            }
            // Cu bitul încă pus, copia ar porni izolată și ar cere mutarea din
            // nou — exact bucla pe care o repară acest fișier.
            if let flags = quarantineFlags(destination), flags & translocateFlag != 0 {
                throw failure("copia din /Applications a rămas marcată pentru izolare")
            }
            log.info("Copiată în \(destination.path)" + (quarantineFlags(destination).map { String(format: " (carantină %04x)", $0) } ?? ""))
            relaunchAfterExit(destination)
            // Originalul la Coș (recuperabil) — niciodată copia tocmai instalată.
            if !isSameFile(original, destination) {
                do {
                    try FileManager.default.trashItem(at: original, resultingItemURL: nil)
                    log.info("Originalul mutat la Coș: \(original.path)")
                } catch {
                    log.warning("Originalul rămâne în \(original.path): \(error.localizedDescription)")
                }
            }
            DiagnosticLog.flush()
            NSApp.terminate(nil)
        } catch {
            fail(error)
        }
    }

    /// Deja în folderul Aplicații, dar izolată: doar atributul, apoi repornire.
    private static func repairInPlace(_ target: URL) {
        guard let value = quarantineWithoutTranslocation(at: target) else {
            // Fără bit de scos, o repornire ar fi la fel de izolată — nu intrăm în buclă.
            log.warning("Izolată, dar fără bitul 0x0080 pe \(target.path) — rulez așa")
            return
        }
        do {
            if FileManager.default.isWritableFile(atPath: target.path) {
                try writeQuarantine(value, to: target)
            } else {
                try runAsAdmin("/usr/bin/xattr -w \(quarantineKey) \(shellQuote(value)) \(shellQuote(target.path))")
            }
            log.info("Izolarea scoasă; repornesc din \(target.path)")
            relaunchAfterExit(target)
            DiagnosticLog.flush()
            NSApp.terminate(nil)
        } catch {
            fail(error)
        }
    }

    private static func fail(_ error: Error) {
        log.error("Mutarea în /Applications a eșuat: \(error.localizedDescription)")
        let wasAccessory = bringToFront()
        let alert = NSAlert()
        alert.messageText = "Mutare eșuată"
        alert.informativeText = "Nu am putut muta aplicația automat (\(error.localizedDescription)). Mut-o manual în /Applications din Finder."
        alert.alertStyle = .warning
        alert.runModal()
        if wasAccessory { NSApp.setActivationPolicy(.accessory) }
    }

    /// O aplicație fără Dock (`.accessory`) poate lăsa alerta în spatele altor
    /// ferestre; pe durata întrebării devine una obișnuită. Întoarce `true`
    /// dacă politica trebuie restaurată.
    private static func bringToFront() -> Bool {
        let wasAccessory = NSApp.activationPolicy() == .accessory
        if wasAccessory { NSApp.setActivationPolicy(.regular) }
        NSApp.activate(ignoringOtherApps: true)
        return wasAccessory
    }

    /// O instanță care rulează deja (ex. o versiune veche din /Applications)
    /// ar fi reactivată de `open` în locul copiei noi.
    private static func terminateOtherInstances() {
        let me = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0.processIdentifier != me }
        guard !others.isEmpty else { return }
        log.info("Închid instanțele care rulează deja: \(others.map { String($0.processIdentifier) }.joined(separator: ", "))")
        others.forEach { $0.terminate() }
        let deadline = Date().addingTimeInterval(5)
        while others.contains(where: { !$0.isTerminated }), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        others.filter { !$0.isTerminated }.forEach { $0.forceTerminate() }
    }

    /// Copie alături + înlocuire, ca o copie veche să nu dispară înainte ca cea
    /// nouă să fie completă. O copie veche deținută de root (instalată din
    /// .pkg) sau un /Applications fără drept de scriere cer parola de administrator.
    private static func install(_ source: URL, quarantine: String?) throws {
        let fm = FileManager.default
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".\(destination.lastPathComponent).new")
        let existingWritable = !fm.fileExists(atPath: destination.path) || fm.isWritableFile(atPath: destination.path)
        if existingWritable, fm.isWritableFile(atPath: destination.deletingLastPathComponent().path) {
            try? fm.removeItem(at: staging)
            try fm.copyItem(at: source, to: staging)
            if let quarantine { try writeQuarantine(quarantine, to: staging) }
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.moveItem(at: staging, to: destination)
            return
        }
        log.info("Instalarea în /Applications cere drepturi de administrator")
        var steps = ["rm -rf \(shellQuote(staging.path))", "/usr/bin/ditto \(shellQuote(source.path)) \(shellQuote(staging.path))"]
        if let quarantine { steps.append("/usr/bin/xattr -w \(quarantineKey) \(shellQuote(quarantine)) \(shellQuote(staging.path))") }
        steps += ["rm -rf \(shellQuote(destination.path))", "mv \(shellQuote(staging.path)) \(shellQuote(destination.path))"]
        try runAsAdmin(steps.joined(separator: " && "))
    }

    /// `open` cât timp procesul ăsta încă rulează ar reactiva instanța curentă
    /// (același bundle ID) în loc să pornească copia nouă — așteptăm ieșirea.
    private static func relaunchAfterExit(_ target: URL) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$1\"", "sh", target.path]
        try? task.run()
    }

    private static func failure(_ message: String) -> Error {
        CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: message])
    }

    // MARK: - Locație

    private static func isRunningFromXcodeOrTests(_ url: URL) -> Bool {
        let path = url.path
        return path.contains("/DerivedData/") || path.contains("/.build/") || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// `/Applications` sau `~/Applications` (Regula 18), judecat pe calea
    /// originalului — sub App Translocation, calea procesului e mereu alta.
    private static func isInApplicationsFolder(_ url: URL) -> Bool {
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        let userApps = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
        return ["/Applications/", userApps + "/"].contains { path.hasPrefix($0) || path.hasPrefix("/System/Volumes/Data" + $0) }
    }

    /// Același fișier pe disc (nu doar același text de cale): prinde și
    /// `/System/Volumes/Data/Applications/…` sau o cale cu link simbolic.
    private static func isSameFile(_ a: URL, _ b: URL) -> Bool {
        let key: Set<URLResourceKey> = [.fileResourceIdentifierKey]
        if let idA = try? a.resourceValues(forKeys: key).fileResourceIdentifier,
           let idB = try? b.resourceValues(forKeys: key).fileResourceIdentifier {
            return idA.isEqual(idB)
        }
        return a.resolvingSymlinksInPath().standardizedFileURL.path == b.resolvingSymlinksInPath().standardizedFileURL.path
    }

    /// Sub App Translocation, originalul (cel de mutat și de dus la Coș) se află
    /// prin Security.framework — API fără header public, același folosit de LetsMove.
    private static func originalLocation(of url: URL) -> URL {
        typealias IsTranslocated = @convention(c) (CFURL, UnsafeMutablePointer<Bool>, UnsafeMutableRawPointer?) -> DarwinBoolean
        typealias OriginalPath = @convention(c) (CFURL, UnsafeMutableRawPointer?) -> Unmanaged<CFURL>?
        guard let handle = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY) else { return url }
        defer { dlclose(handle) }
        guard let isSymbol = dlsym(handle, "SecTranslocateIsTranslocatedURL"),
              let originalSymbol = dlsym(handle, "SecTranslocateCreateOriginalPathForURL") else { return url }
        var translocated = false
        guard unsafeBitCast(isSymbol, to: IsTranslocated.self)(url as CFURL, &translocated, nil).boolValue, translocated,
              let original = unsafeBitCast(originalSymbol, to: OriginalPath.self)(url as CFURL, nil)?.takeRetainedValue()
        else { return url }
        return original as URL
    }

    /// Citit direct din Info.plist: `Bundle(url:)` ține în cache bundle-urile
    /// deja deschise după cale.
    private static func version(of app: URL) -> String? {
        NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))?["CFBundleShortVersionString"] as? String
    }

    // MARK: - Carantină

    private static func readQuarantine(_ url: URL) -> String? {
        url.withUnsafeFileSystemRepresentation { path -> String? in
            guard let path else { return nil }
            let size = getxattr(path, quarantineKey, nil, 0, 0, XATTR_NOFOLLOW)
            guard size > 0 else { return nil }
            var buffer = [UInt8](repeating: 0, count: size)
            guard getxattr(path, quarantineKey, &buffer, size, 0, XATTR_NOFOLLOW) == size else { return nil }
            return String(decoding: buffer, as: UTF8.self)
        }
    }

    private static func quarantineFlags(_ url: URL) -> UInt32? {
        readQuarantine(url).flatMap { $0.split(separator: ";").first }.flatMap { UInt32($0, radix: 16) }
    }

    /// Atributul fără bitul de izolare; nil dacă nu e carantină sau bitul lipsește.
    private static func quarantineWithoutTranslocation(at url: URL) -> String? {
        guard let value = readQuarantine(url), let flags = quarantineFlags(url), flags & translocateFlag != 0 else { return nil }
        let rest = value.split(separator: ";", omittingEmptySubsequences: false).dropFirst()
        return ([String(format: "%04x", flags & ~translocateFlag)] + rest.map(String.init)).joined(separator: ";")
    }

    private static func writeQuarantine(_ value: String, to url: URL) throws {
        let result = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            let bytes = Array(value.utf8)
            return setxattr(path, quarantineKey, bytes, bytes.count, 0, XATTR_NOFOLLOW)
        }
        if result != 0 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EPERM) }
    }

    // MARK: - Administrator

    private static func shellQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func runAsAdmin(_ shell: String) throws {
        let escaped = shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "do shell script \"\(escaped)\" with administrator privileges"]
        let errPipe = Pipe()
        process.standardError = errPipe
        try process.run()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw failure(message.isEmpty ? "acces refuzat" : message)
        }
    }
}
