import Combine
import Foundation

struct SuggestedAction: Identifiable {
    let id = UUID()
    let title: String
    let icon: String // SF Symbol
    let kind: Kind
    enum Kind { case purgeCache, bypassFX, revealCacheFolder }
}

/// O alertă din log-ul DaVinci, afișată în lista vizuală a overlay-ului
/// (icon + text scurt + severitate) — nu un tabel, un jurnal compact.
struct AlertEntry: Identifiable {
    let id = UUID()
    let icon: String
    let text: String
    let level: MetricLevel
    let date: Date = Date()
}

/// Leagă semnalele din SystemMetrics + DaVinciLogWatcher de starea vizuală a overlay-ului.
final class OverlayViewModel: ObservableObject {
    @Published var ramFraction: Double = 0
    @Published var swapFraction: Double = 0
    @Published var vramUsedGB: Double?
    @Published var ramLevel: MetricLevel = .ok
    @Published var swapLevel: MetricLevel = .ok
    @Published var overallLevel: MetricLevel = .ok
    @Published var suggestedAction: SuggestedAction?
    @Published var recentAlerts: [AlertEntry] = []
    @Published var diskFreeGB: Double?
    @Published var diskLevel: MetricLevel = .ok

    private static let maxAlerts = 5
    private var cancellables = Set<AnyCancellable>()
    private var diskCheckTimer: Timer?

    init(metrics: SystemMetrics, logWatcher: DaVinciLogWatcher?) {
        metrics.snapshotPublisher
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in self?.apply(snapshot) }
            .store(in: &cancellables)

        logWatcher?.signalPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] signal in self?.apply(signal) }
            .store(in: &cancellables)

        checkDiskSpace()
        // Alertă de Stocare: verificare rară (60s), niciodată polling agresiv.
        diskCheckTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.checkDiskSpace()
        }
    }

    private func checkDiskSpace() {
        diskFreeGB = CacheFolderLocator.freeDiskSpaceGB()
        guard let free = diskFreeGB else { return }
        diskLevel = free < 10 ? .critical : (free < 50 ? .warning : .ok)
    }

    private func apply(_ snapshot: MemorySnapshot) {
        ramFraction = min(snapshot.ramUsedGB / max(snapshot.ramTotalGB, 1), 1)
        swapFraction = min(snapshot.swapUsedGB / 8.0, 1) // scală vizuală 0-8GB
        vramUsedGB = snapshot.vramUsedGB
        swapLevel = snapshot.swapLevel
        ramLevel = ramFraction > 0.9 ? .critical : (ramFraction > 0.75 ? .warning : .ok)
        overallLevel = [ramLevel, swapLevel].contains(.critical) ? .critical
            : ([ramLevel, swapLevel].contains(.warning) ? .warning : .ok)

        if swapLevel == .critical {
            suggestedAction = SuggestedAction(title: String(localized: "action.purgeCache", bundle: .module), icon: "trash.circle", kind: .purgeCache)
        }
    }

    private func apply(_ signal: ResolveLogSignal) {
        let entry: AlertEntry
        switch signal {
        case .pluginCrash(let name):
            entry = AlertEntry(icon: "exclamationmark.triangle.fill", text: "Plugin crăpat: \(name)", level: .critical)
        case .gpuMemoryFull:
            entry = AlertEntry(icon: "memorychip.fill", text: "GPU Memory Full", level: .critical)
            suggestedAction = SuggestedAction(title: String(localized: "action.bypassFX", bundle: .module), icon: "bolt.slash.circle", kind: .bypassFX)
        case .droppedFrames(let count):
            entry = AlertEntry(icon: "film.stack", text: "\(count) cadre pierdute (I/O)", level: .warning)
        case .renderCacheRegenerated:
            entry = AlertEntry(icon: "arrow.triangle.2.circlepath", text: "Render Cache regenerat", level: .warning)
            suggestedAction = SuggestedAction(title: String(localized: "action.purgeCache", bundle: .module), icon: "trash.circle", kind: .purgeCache)
        case .fusionSlowNode(let ms):
            entry = AlertEntry(icon: "point.3.connected.trianglepath.dotted", text: "Nod Fusion lent (\(ms)ms)", level: .warning)
            suggestedAction = SuggestedAction(title: String(localized: "action.bypassFX", bundle: .module), icon: "bolt.slash.circle", kind: .bypassFX)
        case .codecSoftwareFallback:
            entry = AlertEntry(icon: "cpu", text: "Decodare software (fallback codec)", level: .warning)
        case .dbConnectionLost:
            entry = AlertEntry(icon: "externaldrive.trianglebadge.exclamationmark", text: "Conexiune bază de date pierdută", level: .critical)
        }
        recentAlerts.insert(entry, at: 0)
        if recentAlerts.count > Self.maxAlerts { recentAlerts.removeLast() }
    }

    func perform(_ action: SuggestedAction) {
        switch action.kind {
        case .purgeCache, .revealCacheFolder:
            // Acțiune SIGURĂ, nu distructivă: deschide folderul CacheClip în
            // Finder — ștergerea automată a cache-ului DaVinci fără control
            // exact al proiectului activ e prea riscantă (poate fi cache
            // dintr-un proiect încă folosit). Userul alege ce șterge.
            CacheFolderLocator.revealInFinder()
        case .bypassFX:
            // TODO real: necesită DaVinci Resolve Scripting API conectat
            // (activare/dezactivare FX pe timeline) — neimplementat încă,
            // vezi docs/ARCHITECTURE.md TODO. Deocamdată doar deschide
            // Resolve la Preferences ca indiciu pentru user.
            break
        }
        suggestedAction = nil
    }
}
