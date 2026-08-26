import Foundation
import Combine

/// Semnale detectate în log-urile DaVinci Resolve.
enum ResolveLogSignal: Equatable {
    case pluginCrash(name: String)
    case gpuMemoryFull
    case droppedFrames(count: Int)
    case renderCacheRegenerated
    case fusionSlowNode(ms: Int)
    case codecSoftwareFallback(codec: String)
    case dbConnectionLost
}

/// Ascultă pasiv (FSEvents) fișierul de log activ al DaVinci Resolve
/// și publică semnale parsate, fără polling agresiv.
final class DaVinciLogWatcher {

    private var stream: FSEventStreamRef?
    private var lastOffset: UInt64 = 0
    private let logURL: URL
    let signalPublisher = PassthroughSubject<ResolveLogSignal, Never>()

    init?() {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Blackmagic Design/DaVinci Resolve/logs")
        guard let latest = DaVinciLogWatcher.latestLogFile(in: base) else { return nil }
        self.logURL = latest
    }

    static func latestLogFile(in dir: URL) -> URL? {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return nil }
        return files.filter { $0.pathExtension == "log" }
            .max { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return da < db
            }
    }

    func start() {
        lastOffset = (try? FileManager.default.attributesOfItem(atPath: logURL.path)[.size] as? UInt64) ?? 0

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, clientCallBackInfo, _, _, _, _ in
            guard let info = clientCallBackInfo else { return }
            let watcher = Unmanaged<DaVinciLogWatcher>.fromOpaque(info).takeUnretainedValue()
            watcher.readNewLines()
        }

        stream = FSEventStreamCreate(
            nil, callback, &context,
            [logURL.deletingLastPathComponent().path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            2.5, // latency ~2-3s, conform Regulii de polling pasiv
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents)
        )
        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue(label: "mediaflow.logwatcher", qos: .utility))
        FSEventStreamStart(stream)
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    /// Citește doar octeții noi (tail), niciodată tot fișierul.
    private func readNewLines() {
        guard let handle = try? FileHandle(forReadingFrom: logURL) else { return }
        defer { try? handle.close() }
        try? handle.seek(toOffset: lastOffset)
        let data = handle.readDataToEndOfFile()
        lastOffset += UInt64(data.count)
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return }

        text.split(separator: "\n").forEach { line in
            if let signal = Self.parse(line: String(line)) {
                signalPublisher.send(signal)
            }
        }
    }

    static func parse(line: String) -> ResolveLogSignal? {
        if line.contains("GPU Memory Full") { return .gpuMemoryFull }
        if line.contains("Render Cache regenerated") { return .renderCacheRegenerated }
        if line.contains("Database connection lost") { return .dbConnectionLost }
        if let range = line.range(of: #"OFX plugin .* crashed: (\w+)"#, options: .regularExpression) {
            return .pluginCrash(name: String(line[range]))
        }
        if let range = line.range(of: #"dropped (\d+) frames"#, options: .regularExpression),
           let num = Int(line[range].filter(\.isNumber)) {
            return .droppedFrames(count: num)
        }
        if let range = line.range(of: #"Fusion: comp render time (\d+)ms"#, options: .regularExpression),
           let num = Int(line[range].filter(\.isNumber)) {
            return .fusionSlowNode(ms: num)
        }
        if line.contains("decode fallback to software") { return .codecSoftwareFallback(codec: "unknown") }
        return nil
    }
}
