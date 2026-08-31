import AppKit
import Combine
import Foundation
import UserNotifications

/// Nivel de filtrare a consolei "Real-time Log Decoder".
enum LogFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case errors = "Errors"
    case warnings = "Warnings"
    case renderEvents = "Render Events"
    var id: String { rawValue }
}

struct LogConsoleEntry: Identifiable {
    let id = UUID()
    let date: Date
    let text: String
    let level: MetricLevel
    let isRenderEvent: Bool
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
    case purgeCache, forceSyncLog, optimiseSystem, forceKillDaVinci
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
    @Published var gpuUtilizationPercent: Double?
    @Published var thermalState: ThermalState = .nominal
    @Published var cpuPerCore: [Double] = []
    @Published var topRamProcesses: [ProcessUsage] = []
    @Published var topSwapProcesses: [ProcessUsage] = []

    @Published var diskInfo: DiskInfo?
    @Published var cachePathIsManual: Bool = false

    // Log Decoder — filtre, freeze, export.
    @Published var logFilter: LogFilter = .all
    @Published var isLogPaused: Bool = false
    private var pausedLogBuffer: [LogConsoleEntry] = []

    var filteredLogConsole: [LogConsoleEntry] {
        switch logFilter {
        case .all: return logConsole
        case .errors: return logConsole.filter { $0.level == .critical }
        case .warnings: return logConsole.filter { $0.level == .warning }
        case .renderEvents: return logConsole.filter { $0.isRenderEvent }
        }
    }

    var errorCount: Int { logConsole.filter { $0.level == .critical }.count }
    var warningCount: Int { logConsole.filter { $0.level == .warning }.count }

    // Zombie DaVinci Resolve.
    @Published var hangingDaVinciDetected: Bool = false

    // Alerte native (System Banners) — trimise o singură dată per prag depășit.
    private var swapBannerSent = false
    private var diskBannerSent = false

    @Published var vramHistory: [HistoryPoint] = []
    @Published var swapHistory: [HistoryPoint] = []
    @Published var cpuAvgHistory: [HistoryPoint] = []
    @Published var gpuHistory: [HistoryPoint] = []

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
    private let gpuHistoryStore = MetricsHistory()

    private var cancellables = Set<AnyCancellable>()
    private var diskCheckTimer: Timer?
    private let logWatcher: DaVinciLogWatcher?
    private let thermalMonitor = ThermalMonitor()
    private var thermalBannerSent = false

    init(metrics: SystemMetrics, logWatcher: DaVinciLogWatcher?) {
        self.logWatcher = logWatcher

        metrics.snapshotPublisher
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in self?.apply(snapshot) }
            .store(in: &cancellables)

        thermalMonitor.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.apply(thermalState: state) }
            .store(in: &cancellables)
        thermalMonitor.start()

        logWatcher?.signalPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] signal in self?.apply(signal) }
            .store(in: &cancellables)

        cachePathIsManual = CacheFolderLocator.isManualOverride
        checkDisk()
        checkHangingDaVinci()
        diskCheckTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.checkDisk()
            self?.checkHangingDaVinci()
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    deinit {
        thermalMonitor.stop()
    }

    private func checkDisk() {
        diskInfo = CacheFolderLocator.diskInfo()
        if let disk = diskInfo {
            if disk.freeGB < 10 {
                sendBanner(id: "disk-low", title: "CacheClip disk aproape plin", body: String(format: "Doar %.1f GB liberi — golește cache-ul cât mai curând.", disk.freeGB), once: &diskBannerSent)
            } else {
                diskBannerSent = false
            }
        }
        updateRecommendations()
    }

    /// Verifică dacă procesul DaVinci Resolve a rămas agățat: găsit ca
    /// proces activ (`ProcessInspector`), dar NU mai apare ca aplicație
    /// lansată normal (Dock/Cmd+Tab) — semn clar că userul a "închis-o", dar
    /// procesul (sau un helper al lui) a rămas în memorie.
    private func checkHangingDaVinci() {
        let pids = ProcessInspector.davinciProcessPIDs()
        hangingDaVinciDetected = !pids.isEmpty && !ProcessInspector.isDaVinciResolveAppVisible()
        updateRecommendations()
    }

    private func sendBanner(id: String, title: String, body: String, once flag: inout Bool) {
        guard !flag else { return }
        flag = true
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func apply(thermalState state: ThermalState) {
        thermalState = state
        if state >= .serious {
            sendBanner(id: "thermal-high", title: "Sistem supraîncălzit",
                       body: "Nivel termic: \(state.label). Randarea poate încetini (throttling).", once: &thermalBannerSent)
        } else {
            thermalBannerSent = false
        }
        recomputeOverallLevel()
        updateRecommendations()
    }

    private func recomputeOverallLevel() {
        let levels = [ramLevel, swapLevel, thermalState.level]
        overallLevel = levels.contains(.critical) ? .critical
            : (levels.contains(.warning) ? .warning : .ok)
    }

    private func apply(_ snapshot: MemorySnapshot) {
        ramFraction = min(snapshot.ramUsedGB / max(snapshot.ramTotalGB, 1), 1)
        swapFraction = min(snapshot.swapUsedGB / 8.0, 1)
        vramUsedGB = snapshot.vramUsedGB
        gpuUtilizationPercent = snapshot.gpuUtilizationPercent
        cpuPerCore = snapshot.cpuPerCore
        topRamProcesses = snapshot.topRamProcesses
        topSwapProcesses = snapshot.topSwapProcesses
        swapLevel = snapshot.swapLevel
        ramLevel = ramFraction > 0.9 ? .critical : (ramFraction > 0.75 ? .warning : .ok)
        recomputeOverallLevel()

        if let vram = snapshot.vramUsedGB {
            vramHistoryStore.append(vram * 1024) // MB, ca în mockup
            vramHistory = vramHistoryStore.points
        }
        swapHistoryStore.append(snapshot.swapUsedGB * 1024)
        swapHistory = swapHistoryStore.points

        if let gpu = snapshot.gpuUtilizationPercent {
            gpuHistoryStore.append(gpu)
            gpuHistory = gpuHistoryStore.points
        }

        let avgCpu = snapshot.cpuPerCore.isEmpty ? 0 : snapshot.cpuPerCore.reduce(0, +) / Double(snapshot.cpuPerCore.count) * 100
        cpuHistoryStore.append(avgCpu)
        cpuAvgHistory = cpuHistoryStore.points

        if swapLevel == .critical {
            suggestedAction = SuggestedAction(title: "Purge Cache", icon: "trash.circle", kind: .purgeCache)
        }
        if swapFraction > 0.8 {
            sendBanner(id: "swap-high", title: "Swap sistem ridicat", body: String(format: "Swap la %.0f%% — editorul poate deveni lent.", swapFraction * 100), once: &swapBannerSent)
        } else {
            swapBannerSent = false
        }
        updateRecommendations()
    }

    private func apply(_ signal: ResolveLogSignal) {
        let (text, level, isRenderEvent): (String, MetricLevel, Bool)
        switch signal {
        case .pluginCrash(let name): (text, level, isRenderEvent) = ("Plugin crashed: \(name)", .critical, false)
        case .gpuMemoryFull:
            (text, level, isRenderEvent) = ("GPU Memory Full", .critical, true)
            suggestedAction = SuggestedAction(title: "Bypass FX", icon: "bolt.slash.circle", kind: .bypassFX)
        case .droppedFrames(let count): (text, level, isRenderEvent) = ("Timeline dropped frame (\(count))", .warning, true)
        case .renderCacheRegenerated:
            (text, level, isRenderEvent) = ("Render Cache invalid — regenerated", .warning, true)
            suggestedAction = SuggestedAction(title: "Purge Cache", icon: "trash.circle", kind: .purgeCache)
        case .fusionSlowNode(let ms):
            (text, level, isRenderEvent) = ("Fusion composition slow rendering (\(ms)ms)", .warning, true)
            suggestedAction = SuggestedAction(title: "Bypass FX", icon: "bolt.slash.circle", kind: .bypassFX)
        case .codecSoftwareFallback: (text, level, isRenderEvent) = ("Codec fallback to software decode", .warning, false)
        case .dbConnectionLost: (text, level, isRenderEvent) = ("Database connection lost", .critical, false)
        }

        let entry = LogConsoleEntry(date: Date(), text: text, level: level, isRenderEvent: isRenderEvent)
        if isLogPaused {
            pausedLogBuffer.insert(entry, at: 0)
        } else {
            logConsole.insert(entry, at: 0)
            if logConsole.count > Self.maxConsoleLines {
                logConsole.removeLast(logConsole.count - Self.maxConsoleLines)
            }
        }
        updateRecommendations()
    }

    /// Pause/Resume Auto-scroll — cât e pe pauză, evenimentele noi se
    /// acumulează separat (nu se pierd), și se reinjectează la Resume.
    func toggleLogPause() {
        isLogPaused.toggle()
        if !isLogPaused, !pausedLogBuffer.isEmpty {
            logConsole.insert(contentsOf: pausedLogBuffer, at: 0)
            if logConsole.count > Self.maxConsoleLines {
                logConsole.removeLast(logConsole.count - Self.maxConsoleLines)
            }
            pausedLogBuffer.removeAll()
        }
    }

    /// Export Log — salvează consola curentă (filtrată după `logFilter`)
    /// într-un fișier .txt, un singur click, pentru trimis la suport.
    func exportLog() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "MediaFlowMonitor-Log-\(Int(Date().timeIntervalSince1970)).txt"
        panel.allowedContentTypes = [.plainText]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            let lines = self.filteredLogConsole.reversed().map { entry -> String in
                let tag = entry.level == .critical ? "ERR" : (entry.level == .warning ? "WARN" : "OK")
                return "\(formatter.string(from: entry.date)) [\(tag)] \(entry.text)"
            }
            try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Accesorii & utilitare rapide

    func openCacheFolderInFinder() {
        CacheFolderLocator.revealInFinder()
    }

    /// Copy Diagnostics — rezumat curat, gata de lipit în WhatsApp/email/forum.
    func copyDiagnosticsToClipboard() {
        var lines: [String] = []
        lines.append("MediaFlow Monitor — Diagnostic")
        lines.append("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append(String(format: "RAM: %.1f%% (nivel %@)", ramFraction * 100, levelText(ramLevel)))
        lines.append(String(format: "Swap: %.1f%% (nivel %@)", swapFraction * 100, levelText(swapLevel)))
        lines.append("VRAM: \(vramUsedGB.map { String(format: "%.1f GB", $0) } ?? "necunoscut")")
        lines.append("GPU: \(gpuUtilizationPercent.map { String(format: "%.0f%%", $0) } ?? "necunoscut")")
        lines.append("Thermal: \(thermalState.label)")
        if let disk = diskInfo {
            lines.append(String(format: "CacheClip disk: %.1f GB liberi din %.0f GB (%@)", disk.freeGB, disk.totalGB, disk.path.path))
        }
        let recentErrors = logConsole.filter { $0.level == .critical }.prefix(5)
        if !recentErrors.isEmpty {
            lines.append("Ultimele erori din log:")
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            for e in recentErrors { lines.append("  \(formatter.string(from: e.date)) — \(e.text)") }
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(lines.joined(separator: "\n"), forType: .string)
        actionToast = (text: "Diagnostic copiat în clipboard", success: true)
    }

    private func levelText(_ level: MetricLevel) -> String {
        switch level {
        case .ok: return "OK"
        case .warning: return "Atenție"
        case .critical: return "Critic"
        }
    }

    /// Force Close Hanging DaVinci — apare doar când procesul e detectat
    /// agățat (vezi `checkHangingDaVinci`), niciodată în timp ce Resolve
    /// rulează normal cu fereastră vizibilă.
    func forceCloseHangingDaVinci() {
        guard runningAction == nil else { return }
        beginAction(.forceKillDaVinci)
        actionLog.removeAll()
        logStep("[INFO] Force Close Hanging DaVinci started…", .info)
        Task { @MainActor in
            await self.stepDelay()
            let count = ProcessInspector.forceKillHangingDaVinci()
            await self.stepDelay()
            if count > 0 {
                self.logStep("[SUCCESS] Închise \(count) proces(e) DaVinci Resolve agățate.", .success)
                self.hangingDaVinciDetected = false
                self.endAction(success: true, toast: "DaVinci Resolve închis forțat")
            } else {
                self.logStep("[INFO] Niciun proces agățat găsit.", .info)
                self.endAction(success: true, toast: "Nimic de închis")
            }
            self.updateRecommendations()
        }
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
        if hangingDaVinciDetected {
            items.append(Recommendation(text: "DaVinci Resolve pare agățat în fundal (blochează RAM/VRAM) — Force Close Hanging DaVinci", level: .critical))
        }
        if thermalState == .critical {
            items.append(Recommendation(text: "Thermal: sistem critic — throttling activ, randarea va încetini", level: .critical))
        } else if thermalState == .serious {
            items.append(Recommendation(text: "Thermal: sistem încălzit — throttling probabil în curând", level: .warning))
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
