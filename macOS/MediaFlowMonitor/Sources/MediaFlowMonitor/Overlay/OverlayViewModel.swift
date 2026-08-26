import Combine
import Foundation

struct SuggestedAction: Identifiable {
    let id = UUID()
    let title: String
    let icon: String // SF Symbol
    let kind: Kind
    enum Kind { case purgeCache, bypassFX, revealCacheFolder }
}

/// Leagă semnalele din SystemMetrics + DaVinciLogWatcher de starea vizuală a overlay-ului.
final class OverlayViewModel: ObservableObject {
    @Published var ramFraction: Double = 0
    @Published var swapFraction: Double = 0
    @Published var ramLevel: MetricLevel = .ok
    @Published var swapLevel: MetricLevel = .ok
    @Published var overallLevel: MetricLevel = .ok
    @Published var suggestedAction: SuggestedAction?

    private var cancellables = Set<AnyCancellable>()

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
    }

    private func apply(_ snapshot: MemorySnapshot) {
        ramFraction = min(snapshot.ramUsedGB / max(snapshot.ramTotalGB, 1), 1)
        swapFraction = min(snapshot.swapUsedGB / 8.0, 1) // scală vizuală 0-8GB
        swapLevel = snapshot.swapLevel
        ramLevel = ramFraction > 0.9 ? .critical : (ramFraction > 0.75 ? .warning : .ok)
        overallLevel = [ramLevel, swapLevel].contains(.critical) ? .critical
            : ([ramLevel, swapLevel].contains(.warning) ? .warning : .ok)

        if swapLevel == .critical {
            suggestedAction = SuggestedAction(title: String(localized: "action.purgeCache", bundle: .module), icon: "trash.circle", kind: .purgeCache)
        }
    }

    private func apply(_ signal: ResolveLogSignal) {
        switch signal {
        case .gpuMemoryFull, .fusionSlowNode:
            suggestedAction = SuggestedAction(title: String(localized: "action.bypassFX", bundle: .module), icon: "bolt.slash.circle", kind: .bypassFX)
        case .renderCacheRegenerated:
            suggestedAction = SuggestedAction(title: String(localized: "action.purgeCache", bundle: .module), icon: "trash.circle", kind: .purgeCache)
        default:
            break
        }
    }

    func perform(_ action: SuggestedAction) {
        // TODO: integrare reală (AppleScript/Resolve API) — placeholder în această fază.
        suggestedAction = nil
    }
}
