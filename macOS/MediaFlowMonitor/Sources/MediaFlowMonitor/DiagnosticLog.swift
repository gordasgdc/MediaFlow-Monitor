import Foundation
import os.log

/// Logul de diagnostic al aplicației (Regulile 25 și 39), port din GDC Firewall.
///
/// Fiecare eveniment ajunge simultan în două locuri:
///   - unified log, subsistemul `com.gdc.mediaflowmonitor` — `log show`, Console;
///   - `~/Library/Logs/MediaFlowMonitor.log` — citibil direct în terminal, o linie
///     per eveniment: `timestamp NIVEL [categorie] mesaj`.
///
/// `scripts/logs.sh` le arată pe amândouă. Nu se loghează parole, chei sau
/// conținut de fișiere.
struct DiagnosticLog {
    enum Level: String {
        case debug = "DEBUG", info = "INFO", warning = "WARN", error = "ERROR"
    }

    static let subsystem = "com.gdc.mediaflowmonitor"
    static let fileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/MediaFlowMonitor.log")
    /// Peste plafon, fișierul devine `MediaFlowMonitor.log.1` și se începe unul nou
    /// (Regula 21: nimic nu crește la nesfârșit).
    static let maxBytes: UInt64 = 5 * 1024 * 1024

    /// `defaults write com.gdc.mediaflowmonitor MediaFlowMonitor.verboseLog -bool true`
    /// trimite și mesajele de nivel debug în fișier (unified log le are oricum).
    static var verbose: Bool { UserDefaults.standard.bool(forKey: "MediaFlowMonitor.verboseLog") }

    let category: String
    private let logger: Logger

    init(_ category: String) {
        self.category = category
        logger = Logger(subsystem: Self.subsystem, category: category)
    }

    /// Golește coada de scriere — la oprire, ca ultima linie să ajungă pe disc.
    static func flush() { LogFile.shared.flush() }

    func debug(_ message: String) { write(.debug, message) }
    func info(_ message: String) { write(.info, message) }
    func warning(_ message: String) { write(.warning, message) }
    func error(_ message: String) { write(.error, message) }

    private func write(_ level: Level, _ message: String) {
        // `.public`: e un log de diagnostic local; ascuns ca „<private>” n-ar
        // mai ajuta la nimic în Console.
        switch level {
        case .debug: logger.debug("\(message, privacy: .public)")
        case .info: logger.info("\(message, privacy: .public)")
        case .warning: logger.warning("\(message, privacy: .public)")
        case .error: logger.error("\(message, privacy: .public)")
        }
        guard level != .debug || Self.verbose else { return }
        LogFile.shared.append(level: level, category: category, message: message)
    }
}

/// Scrierea în fișier: o singură coadă serială, ca liniile venite din fire
/// diferite să nu se amestece.
private final class LogFile {
    static let shared = LogFile()

    private let queue = DispatchQueue(label: "com.gdc.mediaflowmonitor.logfile", qos: .utility)
    private var handle: FileHandle?
    private let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = .current
        return formatter
    }()

    func append(level: DiagnosticLog.Level, category: String, message: String) {
        let date = Date()
        queue.async { [self] in
            let flat = message.replacingOccurrences(of: "\n", with: " ⏎ ")
            let tag = level.rawValue.padding(toLength: 5, withPad: " ", startingAt: 0)
            guard let data = "\(formatter.string(from: date)) \(tag) [\(category)] \(flat)\n".data(using: .utf8) else { return }
            rotateIfNeeded()
            if handle == nil { open() }
            try? handle?.write(contentsOf: data)
        }
    }

    func flush() {
        queue.sync { try? handle?.synchronize() }
    }

    private func open() {
        let url = DiagnosticLog.fileURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        handle = try? FileHandle(forWritingTo: url)
        _ = try? handle?.seekToEnd()
    }

    private func rotateIfNeeded() {
        let url = DiagnosticLog.fileURL
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
        guard size >= DiagnosticLog.maxBytes else { return }
        try? handle?.close()
        handle = nil
        let previous = url.appendingPathExtension("1")
        try? FileManager.default.removeItem(at: previous)
        try? FileManager.default.moveItem(at: url, to: previous)
    }
}
