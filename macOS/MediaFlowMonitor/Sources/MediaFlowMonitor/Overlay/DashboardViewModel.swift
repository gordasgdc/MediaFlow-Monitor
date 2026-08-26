import Combine
import Foundation

struct LogConsoleEntry: Identifiable {
    let id = UUID()
    let date: Date
    let text: String
    let level: MetricLevel
}

struct Recommendation: Identifiable {
    let id = UUID()
    let text: String
    let level: MetricLevel
}

/// Nivel de linie în consola de execuție live (Terminal-style), pentru
/// feedback vizual pe Purge Cache / Force Sync Log / Optimise System —
/// distinct de `MetricLevel` (acela descrie stare de sistem, nu progres).
enum ActionLogLevel {
    case info, exec, success, error
}

struct ActionLogEntry: Identifiable {
    let id = UUID()
    let date: Date
    let text: String
    let level: ActionLogLevel
}

/// Ce buton de acțiune rulează în acest moment — controlează spinner-ul
/// și textul butonului respectiv ("Purging…" etc.).
enum RunningAction: Equatable {
    case purgeCache, forceSyncLog, optimiseSystem
}

struct SuggestedAction: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let kind: Kind
    enum Kind { case purgeCache, bypassFX }
}

/// ViewModel-ul Dashboard-ului Pro — orchestrează metrice, istoricul de
/// grafice, consola de log decodat, recomandările și acțiunile.
final class DashboardViewModel: ObservableObject {
    @Published var ramFraction: Double = 0
    @Published var swapFraction: Double = 0
    @Published var ramLevel: MetricLevel = .ok
    @Published var swapLevel: MetricLevel = .ok
    @Published var overallLevel: MetricLevel = .ok
    @Published var vramUsedGB: Double?
    @Published var cpuPerCore: [Double] = []

    @Published var diskInfo: DiskInfo?
    @Published var cachePathIsManual: Bool = false

    @Published var vramHistory: [HistoryPoint] = []
    @Published var swapHistory: [HistoryPoint] = []
    @Published var cpuAvgHistory: [HistoryPoint] = []

    @Published var logConsole: [LogConsoleEntry] = []
    @Published var recommendations: [Recommendation] = []
    @Published var suggestedAction: SuggestedAction?
    @Published var lastActionMessage: String?

    // Consola de execuție live (Terminal-style) pentru butoanele de acțiune.
    @Published var actionLog: [ActionLogEntry] = []
    @Published var runningAction: RunningAction?
    @Published var showActionConsole: Bool = false
    /// Toast scurt afișat la finalizare (succes sau eșec) — se auto-ascunde.
    @Published var actionToast: (text: String, success: Bool)?

    private static let maxActionLogLines = 200

    private static let maxConsoleLines = 60
    private let vramHistoryStore = MetricsHistory()
    private let swapHistoryStore = MetricsHistory()
    private let cpuHistoryStore = MetricsHistory()

    private var cancellables = Set<AnyCancellable>()
    private var diskCheckTimer: Timer?
    private let logWatcher: DaVinciLogWatcher?

    init(metrics: SystemMetrics, logWatcher: DaVinciLogWatcher?) {
        self.logWatcher = logWatcher

        metrics.snapshotPublisher
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in self?.apply(snapshot) }
            .store(in: &cancellables)

        logWatcher?.signalPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] signal in self?.apply(signal) }
            .store(in: &cancellables)

        cachePathIsManual = CacheFolderLocator.isManualOverride
        checkDisk()
        diskCheckTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.checkDisk()
        }
    }

    private func checkDisk() {
        diskInfo = CacheFolderLocator.diskInfo()
        updateRecommendations()
    }

    private func apply(_ snapshot: MemorySnapshot) {
        ramFraction = min(snapshot.ramUsedGB / max(snapshot.ramTotalGB, 1), 1)
        swapFraction = min(snapshot.swapUsedGB / 8.0, 1)
        vramUsedGB = snapshot.vramUsedGB
        cpuPerCore = snapshot.cpuPerCore
        swapLevel = snapshot.swapLevel
        ramLevel = ramFraction > 0.9 ? .critical : (ramFraction > 0.75 ? .warning : .ok)
        overallLevel = [ramLevel, swapLevel].contains(.critical) ? .critical
            : ([ramLevel, swapLevel].contains(.warning) ? .warning : .ok)

        if let vram = snapshot.vramUsedGB {
            vramHistoryStore.append(vram * 1024) // MB, ca în mockup
            vramHistory = vramHistoryStore.points
        }
        swapHistoryStore.append(snapshot.swapUsedGB * 1024)
        swapHistory = swapHistoryStore.points

        let avgCpu = snapshot.cpuPerCore.isEmpty ? 0 : snapshot.cpuPerCore.reduce(0, +) / Double(snapshot.cpuPerCore.count) * 100
        cpuHistoryStore.append(avgCpu)
        cpuAvgHistory = cpuHistoryStore.points

        if swapLevel == .critical {
            suggestedAction = SuggestedAction(title: "Purge Cache", icon: "trash.circle", kind: .purgeCache)
        }
        updateRecommendations()
    }

    private func apply(_ signal: ResolveLogSignal) {
        let (text, level): (String, MetricLevel)
        switch signal {
        case .pluginCrash(let name): (text, level) = ("Plugin crashed: \(name)", .critical)
        case .gpuMemoryFull:
            (text, level) = ("GPU Memory Full", .critical)
            suggestedAction = SuggestedAction(title: "Bypass FX", icon: "bolt.slash.circle", kind: .bypassFX)
        case .droppedFrames(let count): (text, level) = ("Timeline dropped frame (\(count))", .warning)
        case .renderCacheRegenerated:
            (text, level) = ("Render Cache invalid — regenerated", .warning)
            suggestedAction = SuggestedAction(title: "Purge Cache", icon: "trash.circle", kind: .purgeCache)
        case .fusionSlowNode(let ms):
            (text, level) = ("Fusion composition slow rendering (\(ms)ms)", .warning)
            suggestedAction = SuggestedAction(title: "Bypass FX", icon: "bolt.slash.circle", kind: .bypassFX)
        case .codecSoftwareFallback: (text, level) = ("Codec fallback to software decode", .warning)
        case .dbConnectionLost: (text, level) = ("Database connection lost", .critical)
        }

        logConsole.insert(LogConsoleEntry(date: Date(), text: text, level: level), at: 0)
        if logConsole.count > Self.maxConsoleLines {
            logConsole.removeLast(logConsole.count - Self.maxConsoleLines)
        }
        updateRecommendations()
    }

    private func updateRecommendations() {
        var items: [Recommendation] = []

        if let disk = diskInfo {
            if disk.freeGB < 10 {
                items.append(Recommendation(text: "Action Required: Purge unused Cache (disk critically low)", level: .critical))
            } else if disk.freeGB < 50 {
                items.append(Recommendation(text: "Storage: cache disk approaching full", level: .warning))
            }
            if disk.isHealthy == false {
                items.append(Recommendation(text: "Disk health: SMART reports FAILING — backup immediately", level: .critical))
            }
        }
        if swapLevel == .critical {
            items.append(Recommendation(text: "System Memory: approaching swap limit", level: .critical))
        } else if swapLevel == .warning {
            items.append(Recommendation(text: "System Memory: swap usage rising", level: .warning))
        }
        if logConsole.contains(where: { $0.level == .critical }) {
            items.append(Recommendation(text: "Recent critical event in DaVinci log — check console below", level: .critical))
        }
        if items.isEmpty {
            items.append(Recommendation(text: "All systems normal", level: .ok))
        }
        recommendations = items
    }

    func chooseCacheFolderManually() {
        CacheFolderLocator.chooseFolderManually { [weak self] _ in
            self?.cachePathIsManual = CacheFolderLocator.isManualOverride
            self?.checkDisk()
        }
    }

    // MARK: - Consola de execuție live

    private func logStep(_ text: String, _ level: ActionLogLevel = .exec) {
        actionLog.append(ActionLogEntry(date: Date(), text: text, level: level))
        if actionLog.count > Self.maxActionLogLines {
            actionLog.removeFirst(actionLog.count - Self.maxActionLogLines)
        }
    }

    private func beginAction(_ action: RunningAction) {
        runningAction = action
        showActionConsole = true
        actionToast = nil
    }

    private func endAction(success: Bool, toast: String) {
        runningAction = nil
        actionToast = (text: toast, success: success)
        lastActionMessage = toast
        // Toast-ul dispare singur — consola rămâne deschisă ca să poată fi
        // recitită, userul o închide manual din Dashboard.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if self?.actionToast?.text == toast { self?.actionToast = nil }
        }
    }

    /// Pauză mică între pași — doar UX (utilizatorul trebuie să apuce să
    /// citească fiecare linie), nu simulează timp de execuție fals: pașii
    /// în sine (disk info, purge, forceSync) rulează sincron, real.
    private func stepDelay() async {
        try? await Task.sleep(nanoseconds: 250_000_000)
    }

    func forceSyncLog() {
        guard runningAction == nil else { return }
        beginAction(.forceSyncLog)
        actionLog.removeAll()
        logStep("[INFO] Force Sync Log started…", .info)
        Task { @MainActor in
            await stepDelay()
            logStep("[EXEC] Re-reading DaVinci Resolve log tail…")
            logWatcher?.forceSync()
            await stepDelay()
            logStep("[SUCCESS] Log resynced.", .success)
            endAction(success: true, toast: "Log resynced")
        }
    }

    /// Cere confirmare userului ÎNAINTE de a șterge orice — Purge Cache e
    /// distructiv, niciodată executat fără un pas explicit de confirmare.
    func requestPurgeCache(confirm: @escaping (@escaping (Bool) -> Void) -> Void) {
        guard runningAction == nil else { return }
        confirm { [weak self] approved in
            guard approved, let self else { return }
            self.beginAction(.purgeCache)
            self.actionLog.removeAll()
            self.logStep("[INFO] Purge Cache started…", .info)
            Task { @MainActor in
                await self.stepDelay()
                let path = CacheFolderLocator.activePath
                self.logStep("[INFO] Scanning cache folder: \(path.path)", .info)
                await self.stepDelay()
                let before = CacheFolderLocator.diskInfo()
                if let before {
                    self.logStep(String(format: "[EXEC] %.1f GB free before purge…", before.freeGB))
                }
                do {
                    let count = try CacheFolderLocator.purge()
                    await self.stepDelay()
                    self.logStep("[EXEC] Purged \(count) item(s)…")
                    self.suggestedAction = nil
                    self.checkDisk()
                    if let after = self.diskInfo, let before {
                        let freed = max(after.freeGB - before.freeGB, 0)
                        self.logStep(String(format: "[SUCCESS] System Optimised — freed %.1f GB.", freed), .success)
                    } else {
                        self.logStep("[SUCCESS] Purge Cache completed successfully!", .success)
                    }
                    self.endAction(success: true, toast: "Purged \(count) item(s) from cache")
                } catch {
                    self.logStep("[ERROR] Purge failed: \(error.localizedDescription)", .error)
                    self.endAction(success: false, toast: "Purge failed")
                }
            }
        }
    }

    func optimiseSystem() {
        // Onest: nu există un singur "buton magic" de optimizare sigur —
        // combinăm pașii non-distructivi deja disponibili (sync log +
        // recalcul disc); ștergerea de cache rămâne separată, cu confirmare.
        guard runningAction == nil else { return }
        beginAction(.optimiseSystem)
        actionLog.removeAll()
        logStep("[INFO] Optimise System started…", .info)
        Task { @MainActor in
            await stepDelay()
            logStep("[EXEC] Re-reading DaVinci Resolve log tail…")
            logWatcher?.forceSync()
            await stepDelay()
            logStep("[EXEC] Recalculating CacheClip disk usage…")
            checkDisk()
            await stepDelay()
            if let disk = diskInfo {
                logStep(String(format: "[INFO] %.1f GB free on %@", disk.freeGB, disk.path.path))
            }
            logStep("[SUCCESS] System check refreshed.", .success)
            endAction(success: true, toast: "System check refreshed")
        }
    }
}
