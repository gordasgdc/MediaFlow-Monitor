import SwiftUI
import Charts
import AppKit

private func color(for level: MetricLevel) -> Color {
    switch level {
    case .ok: return .green
    case .warning: return .yellow
    case .critical: return .red
    }
}

struct DashboardView: View {
    @ObservedObject private var vm: DashboardViewModel
    @State private var showPurgeConfirm = false
    @State private var showOptimiseConfirm = false
    @State private var shortcutCopied = false
    @ObservedObject private var prefs = MFMPreferences.shared

    init(metrics: SystemMetrics, logWatcher: DaVinciLogWatcher?) {
        _vm = ObservedObject(wrappedValue: DashboardViewModel(metrics: metrics, logWatcher: logWatcher))
    }

    /// Coloane adaptive: 2 pe lățime confortabilă, colapsează automat la 1
    /// coloană dacă spațiul scade sub `minimum` — nicio suprapunere posibilă,
    /// spre deosebire de un HStack rigid cu frame-uri fixe.
    private let adaptiveColumns = [GridItem(.adaptive(minimum: 280), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                topBar
                shortcutBanner
                LazyVGrid(columns: adaptiveColumns, spacing: 14) {
                    healthCard
                    healthDetailCard
                }
                performanceSection
                LazyVGrid(columns: adaptiveColumns, spacing: 14) {
                    logDecoderPanel
                    recommendationsPanel
                }
                cacheDiskPanel
                actionBar
            }
            .padding(16)
        }
        // Limita minimă absolută e impusă și la nivel de NSWindow
        // (OverlayWindowController.panel.minSize), aici doar oglindim
        // valoarea ca să conținutul SwiftUI nu se comprime niciodată sub ea.
        .frame(minWidth: 800, maxWidth: .infinity, minHeight: 650, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) { toastView }
        .confirmationDialog(
            "Ștergere Cache Disc",
            isPresented: $showPurgeConfirm, titleVisibility: .visible
        ) {
            Button("Șterge Cache", role: .destructive) { purgeCacheNow() }
            Button("Șterge și nu mă mai întreba", role: .destructive) {
                prefs.suppressPurgeWarning = true
                purgeCacheNow()
            }
            Button("Anulează", role: .cancel) {}
        } message: {
            Text("Această acțiune va șterge fișierele temporare de randare din "
                 + "\(CacheFolderLocator.activePath.path) pentru a elibera spațiu. "
                 + "Proiectele video active vor necesita re-randare. Continuați?")
        }
        .confirmationDialog(
            "Optimizare Memorie Sistem",
            isPresented: $showOptimiseConfirm, titleVisibility: .visible
        ) {
            Button("Optimizează") {
                vm.optimiseSystem()
            }
            Button("Anulează", role: .cancel) {}
        } message: {
            Text("Aplicația va elibera memoria RAM inactivă și fișierele temporare din memorie. "
                 + "Procesul este sigur și NU va închide aplicațiile deschise.")
        }
        .sheet(isPresented: $vm.showActionConsole) {
            actionConsoleSheet
        }
    }

    // MARK: - Banner scurtătură

    /// Scurtătura globală, vizibilă permanent.
    ///
    /// Fără ea, un utilizator care închide panoul nu are cum să afle cum îl
    /// aduce înapoi: aplicația n-are icon în Dock, iar iconița din bara de
    /// meniu e ușor de ratat.
    private var shortcutBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "keyboard")
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text("Afișare / Ascundere panou")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 5) {
                    ForEach(Array(MFMPreferences.shortcutKeys.enumerated()), id: \.offset) { _, key in
                        keycap(key)
                    }
                }
            }

            Button {
                let board = NSPasteboard.general
                board.clearContents()
                board.setString(MFMPreferences.shortcutPlainText, forType: .string)
                shortcutCopied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { shortcutCopied = false }
            } label: {
                Image(systemName: shortcutCopied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Copiază scurtătura")

            Spacer()

            Toggle("Pornește minimizat în bara de meniu", isOn: $prefs.startMinimized)
                .toggleStyle(.checkbox)
                .font(.caption)
                .help("La următoarea pornire, panoul nu se mai deschide singur. Îl aduci cu scurtătura de mai sus.")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary, lineWidth: 1))
    }

    /// O tastă fizică desenată: fundal propriu, margine și o umbră de 1px sub
    /// ea, ca un keycap real. Culorile vin exclusiv din materialele
    /// semantice (Regula 37) — arată corect și pe temă deschisă, și pe închisă.
    private func keycap(_ label: String) -> some View {
        Text(label)
            .font(.system(.title3, design: .rounded).weight(.bold))
            .monospacedDigit()
            .foregroundStyle(.primary)
            .frame(minWidth: 34)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.tertiary, lineWidth: 1))
            .shadow(color: .black.opacity(0.18), radius: 0, x: 0, y: 1)
    }

    private func purgeCacheNow() {
        // Confirmarea (sau dezactivarea ei) a avut deja loc — callback-ul de
        // aprobare primește `true` direct.
        vm.requestPurgeCache { callback in callback(true) }
    }

    // MARK: - Live process console (Terminal-style)

    private var actionConsoleSheet: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle().fill(vm.runningAction == nil ? Color.green : Color.yellow).frame(width: 9, height: 9)
                Text(vm.runningAction == nil ? "Proces finalizat" : "Se execută…").font(.headline)
                Spacer()
                if vm.runningAction != nil {
                    ProgressView().controlSize(.small)
                }
                Button("Închide") { vm.showActionConsole = false }
                    .disabled(vm.runningAction != nil)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(vm.actionLog) { entry in
                            Text(entry.text)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(actionLogColor(entry.level))
                                .id(entry.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: vm.actionLog.count) { _ in
                    if let last = vm.actionLog.last?.id {
                        withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
            }
            .padding(10)
            .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(16)
        .frame(width: 520, height: 380)
    }

    private func actionLogColor(_ level: ActionLogLevel) -> Color {
        switch level {
        case .info: return .secondary
        case .exec: return .cyan
        case .success: return .green
        case .error: return .red
        }
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast = vm.actionToast {
            HStack(spacing: 6) {
                Image(systemName: toast.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(toast.success ? .green : .red)
                Text(toast.text).font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThickMaterial, in: Capsule())
            .padding(.bottom, 60)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.easeInOut(duration: 0.25), value: vm.actionToast?.text)
        }
    }

    // MARK: - Top bar (theme selector)

    private var topBar: some View {
        HStack(spacing: 12) {
            Text("MediaFlow Monitor")
                .font(.headline)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 12)
            // BUG FIX: fără `.labelsHidden()`, Picker-ul își desenează
            // propria etichetă ("Temă") ÎN FAȚA segmentelor — într-un
            // HStack strâns, acel text se comprimă vertical, literă cu
            // literă. Eticheta explicită de mai jos înlocuiește eticheta
            // internă a Picker-ului, cu `.fixedSize()` — nu se mai comprimă.
            Text("Temă")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: true, vertical: false)
            Picker("Temă", selection: Binding(
                get: { ThemeManager.shared.current },
                set: { ThemeManager.shared.set($0) }
            )) {
                ForEach(AppTheme.allCases, id: \.self) { theme in
                    Text(theme.label).tag(theme)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .fixedSize()
        }
    }

    // MARK: - System Health

    private var healthCard: some View {
        card {
            HStack {
                Text("System Health").font(.headline)
                Spacer()
                // Calificativ, nu doar un bulin colorat: "Excelent" / "Atenție"
                // se citesc dintr-o privire, un procent cere interpretare.
                let health = vm.healthSummary
                Text(health.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color(for: health.level))
                Circle().fill(color(for: health.level)).frame(width: 10, height: 10)
            }
            Text(vm.healthSummary.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Ce aplicație de montaj rulează acum — contextul în care se
            // citesc toate celelalte cifre.
            HStack(spacing: 6) {
                Circle()
                    .fill(vm.activeNLE == nil ? Color.secondary : Color.green)
                    .frame(width: 7, height: 7)
                if let nle = vm.activeNLE {
                    Text("\(nle.name) activ (PID \(nle.pid))")
                    if nle.ramGB > 0.05 {
                        Text("· \(String(format: "%.1f", nle.ramGB)) GB RAM")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Nicio aplicație de montaj activă").foregroundStyle(.secondary)
                }
                Spacer()
            }
            .font(.caption)
            .help("Detectat automat dintre aplicațiile deschise: DaVinci Resolve, Premiere Pro, Final Cut Pro, After Effects, Avid.")

            HStack(spacing: 20) {
                metricRing(label: "RAM", value: vm.ramFraction, level: vm.ramLevel)
                metricRing(label: "Swap", value: vm.swapFraction, level: vm.swapLevel)
            }
            if !vm.topRamProcesses.isEmpty || !vm.topSwapProcesses.isEmpty {
                Divider()
                HStack(alignment: .top, spacing: 16) {
                    topConsumersList(title: "Top RAM Consumers", items: vm.topRamProcesses, unit: "GB")
                    topConsumersList(title: "Top Swap Activity", items: vm.topSwapProcesses, unit: "GB")
                }
            }
        }
    }

    /// "Swap Activity" (nu "Swap folosit") — macOS nu expune public câți
    /// octeți sunt efectiv scoși pe disc per proces (vezi comentariul din
    /// ProcessInspector.swift); afișăm cea mai onestă aproximare posibilă.
    private func topConsumersList(title: String, items: [ProcessUsage], unit: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            if items.isEmpty {
                Text("—").font(.caption2).foregroundStyle(.secondary)
            }
            ForEach(items) { item in
                HStack {
                    Text(item.name).font(.caption2).lineLimit(1)
                    Spacer(minLength: 6)
                    Text(String(format: "%.1f %@", item.valueGB, unit)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var healthDetailCard: some View {
        card {
            HStack {
                Text("System Health").font(.headline)
                Spacer()
                Circle().fill(color(for: vm.overallLevel)).frame(width: 10, height: 10)
            }
            VStack(alignment: .leading, spacing: 6) {
                detailRow(icon: "cpu", label: "VRAM", value: vm.vramUsedGB.map { String(format: "%.1f GB", $0) } ?? "—")
                detailRow(icon: "gauge.with.dots.needle.67percent", label: "GPU", value: vm.gpuUtilizationPercent.map { String(format: "%.0f%%", $0) } ?? "necunoscut pe acest Mac")
                detailRow(icon: "thermometer.sun", label: "Thermal", value: vm.thermalState.label, dotColor: color(for: vm.thermalState.level))
                detailRow(icon: "internaldrive", label: "Partition", value: vm.diskInfo.map { String(format: "%.0f GB", $0.totalGB) } ?? "—")
                detailRow(icon: "circle.fill", label: "CacheClip disk", value: vm.diskInfo.map { String(format: "%.0f GB liber", $0.freeGB) } ?? "—", dotColor: diskDotColor)
            }
        }
    }

    private var diskDotColor: Color {
        guard let disk = vm.diskInfo else { return .gray }
        if disk.freeGB < 10 { return .red }
        if disk.freeGB < 50 { return .yellow }
        return .green
    }

    // MARK: - Charts

    private var performanceSection: some View {
        card {
            Text("DaVinci Resolve — Real-time Performance & Log Stream").font(.headline)
            LazyVGrid(columns: adaptiveColumns, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("VRAM / Swap Utilization (MB)").font(.caption).foregroundStyle(.secondary)
                    Chart {
                        ForEach(vm.vramHistory) { point in
                            LineMark(x: .value("Time", point.date), y: .value("VRAM", point.value))
                                .foregroundStyle(.blue)
                        }
                        ForEach(vm.swapHistory) { point in
                            LineMark(x: .value("Time", point.date), y: .value("Swap", point.value))
                                .foregroundStyle(.red)
                        }
                    }
                    .chartXAxis(.hidden)
                    .frame(height: 130)
                    .frame(maxWidth: .infinity)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("CPU Thread 1–\(max(vm.cpuPerCore.count, 1))").font(.caption).foregroundStyle(.secondary)
                    Chart {
                        ForEach(Array(vm.cpuPerCore.enumerated()), id: \.offset) { index, usage in
                            BarMark(x: .value("Core", "T\(index + 1)"), y: .value("Usage", usage * 100))
                                .foregroundStyle(usage > 0.85 ? Color.red : (usage > 0.6 ? Color.yellow : Color.green))
                        }
                    }
                    .chartYScale(domain: 0...100)
                    .frame(height: 130)
                    .frame(maxWidth: .infinity)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("GPU Utilization (%)").font(.caption).foregroundStyle(.secondary)
                    if vm.gpuHistory.isEmpty {
                        Text("Necunoscut pe acest Mac").font(.caption2).foregroundStyle(.secondary)
                            .frame(height: 130).frame(maxWidth: .infinity)
                    } else {
                        Chart {
                            ForEach(vm.gpuHistory) { point in
                                LineMark(x: .value("Time", point.date), y: .value("GPU", point.value))
                                    .foregroundStyle(.purple)
                            }
                        }
                        .chartXAxis(.hidden)
                        .chartYScale(domain: 0...100)
                        .frame(height: 130)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    // MARK: - Log decoder

    private static let logKeywords = ["GPU Full", "GPU Memory Full", "Cache Drop", "Timeout", "crashed", "dropped"]

    private var logDecoderPanel: some View {
        card {
            HStack {
                Text("Real-time Log Decoder").font(.headline)
                Spacer()
                Button { vm.exportLog() } label: { Image(systemName: "square.and.arrow.up") }
                    .buttonStyle(.plain)
                    .help("Export Log...")
                Button { vm.toggleLogPause() } label: { Image(systemName: vm.isLogPaused ? "play.fill" : "pause.fill") }
                    .buttonStyle(.plain)
                    .help(vm.isLogPaused ? "Resume Auto-scroll" : "Pause Auto-scroll")
                Button { vm.forceSyncLog() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain)
            }
            HStack(spacing: 6) {
                ForEach(LogFilter.allCases) { filter in
                    logFilterChip(filter)
                }
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        if vm.filteredLogConsole.isEmpty {
                            Text("Niciun eveniment încă — se ascultă log-ul DaVinci Resolve...")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        ForEach(vm.filteredLogConsole) { entry in
                            logLine(entry).id(entry.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: vm.filteredLogConsole.count) { _ in
                    guard !vm.isLogPaused, let first = vm.filteredLogConsole.first?.id else { return }
                    withAnimation { proxy.scrollTo(first, anchor: .top) }
                }
            }
            .frame(height: 160)
        }
        .frame(maxWidth: .infinity)
    }

    private func logFilterChip(_ filter: LogFilter) -> some View {
        let count = filter == .errors ? vm.errorCount : (filter == .warnings ? vm.warningCount : nil)
        return Button {
            vm.logFilter = filter
        } label: {
            HStack(spacing: 4) {
                Text(filter.rawValue).font(.caption2)
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.caption2.bold())
                        .padding(.horizontal, 4)
                        .background(filter == .errors ? Color.red : Color.yellow, in: Capsule())
                        .foregroundStyle(filter == .errors ? .white : .black)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(vm.logFilter == filter ? Color.accentColor.opacity(0.25) : Color.gray.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Timp exact `HH:mm:ss [ERR]` monospațiat, cu highlight pe cuvinte cheie.
    private func logLine(_ entry: LogConsoleEntry) -> some View {
        let tag = entry.level == .critical ? "ERR" : (entry.level == .warning ? "WARN" : "OK")
        var text = AttributedString("\(entry.date.formatted(date: .omitted, time: .standard)) [\(tag)] \(entry.text)")
        text.font = .system(size: 11, design: .monospaced)
        text.foregroundColor = color(for: entry.level)
        for keyword in Self.logKeywords {
            var searchRange = text.startIndex..<text.endIndex
            while let range = text[searchRange].range(of: keyword, options: .caseInsensitive) {
                text[range].font = .system(size: 11, weight: .bold, design: .monospaced)
                text[range].backgroundColor = Color.yellow.opacity(0.25)
                searchRange = range.upperBound..<text.endIndex
            }
        }
        return Text(text)
    }

    // MARK: - Recommendations

    private var recommendationsPanel: some View {
        card {
            Text("Potential Issues & Recommendations").font(.headline)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(vm.recommendations) { rec in
                    HStack(alignment: .top, spacing: 6) {
                        Circle().fill(color(for: rec.level)).frame(width: 8, height: 8).padding(.top, 4)
                        Text(rec.text).font(.system(size: 12))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: - Cache disk detail

    private var cacheDiskPanel: some View {
        card {
            HStack {
                Text("CacheClip disk").font(.headline)
                Spacer()
                Button { vm.openCacheFolderInFinder() } label: { Image(systemName: "folder") }
                    .buttonStyle(.plain)
                    .help("Open Cache Folder in Finder")
                Button("Schimbă folderul…") { vm.chooseCacheFolderManually() }
                    .buttonStyle(.link)
                    .font(.caption)
            }
            if let disk = vm.diskInfo {
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        Rectangle().fill(Color.green)
                            .frame(width: geo.size.width * CGFloat(disk.usedGB / max(disk.totalGB, 1)))
                        Rectangle().fill(Color.gray.opacity(0.3))
                    }
                }
                .frame(height: 8)
                .clipShape(RoundedRectangle(cornerRadius: 4))

                HStack {
                    Text("Disk Usage: \(String(format: "%.1f", disk.usedGB)) GB / \(String(format: "%.0f", disk.totalGB)) GB")
                        .font(.caption)
                    Spacer()
                    HStack(spacing: 4) {
                        Text("Partition Health:").font(.caption)
                        healthBadge(disk.isHealthy)
                    }
                }
                Text(vm.cachePathIsManual ? "Cale (manuală): \(disk.path.path)" : "Cale (auto-detectată): \(disk.path.path)")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            } else {
                Text("Folderul CacheClip nu a fost găsit încă.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func healthBadge(_ healthy: Bool?) -> some View {
        switch healthy {
        case .some(true): Text("Healthy").font(.caption).foregroundStyle(.green)
        case .some(false): Text("Failing").font(.caption).foregroundStyle(.red)
        case .none: Text("Necunoscut").font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Action bar

    private var actionBar: some View {
        // ViewThatFits: încearcă întâi rândul unic; dacă nu încape (fereastră
        // apropiată de minSize, multe butoane simultan), trece la 2 rânduri
        // în loc să comprime/suprapună butoanele.
        ViewThatFits(in: .horizontal) {
            HStack { actionButtons; Spacer(minLength: 8); trailingActionInfo }
            VStack(alignment: .leading, spacing: 8) {
                HStack { actionButtons; Spacer(minLength: 0) }
                HStack { trailingActionInfo }
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        actionButton(title: "Purge Cache", running: .purgeCache, runningTitle: "Purging…") {
            // Avertismentul se poate dezactiva, dar acțiunea rămâne aceeași —
            // vezi "Șterge și nu mă mai întreba" din dialog.
            if prefs.suppressPurgeWarning { purgeCacheNow() } else { showPurgeConfirm = true }
        }
        .help("Șterge fișierele temporare de randare din folderul de cache. Eliberează spațiu pe disc; proiectele active vor fi re-randate.")

        actionButton(title: "Force Sync Log", running: .forceSyncLog, runningTitle: "Syncing…") {
            vm.forceSyncLog()
        }
        .help("Recitește de la zero fișierul de log al DaVinci Resolve. Poate dura o clipă pe loguri mari; nu modifică nimic din proiectele tale.")

        actionButton(title: "Optimise System", running: .optimiseSystem, runningTitle: "Optimising…") {
            if prefs.suppressOptimiseWarning { vm.optimiseSystem() } else { showOptimiseConfirm = true }
        }
        .help("Eliberează memoria RAM inactivă și fișierele temporare din memorie. Sigur — nu închide aplicațiile deschise.")

        Button("Copy Diagnostics") { vm.copyDiagnosticsToClipboard() }
            .help("Copiază în clipboard un rezumat tehnic (sistem, memorie, disc, erori recente) pe care îl poți lipi într-un mesaj către suport.")
        if vm.hangingDaVinciDetected {
            actionButton(title: "Force Close Hanging DaVinci", running: .forceKillDaVinci, runningTitle: "Closing…") {
                vm.forceCloseHangingDaVinci()
            }
            .foregroundStyle(.red)
        }
        if vm.runningAction != nil {
            Button("Vezi log") { vm.showActionConsole = true }
                .buttonStyle(.link).font(.caption)
        }
    }

    @ViewBuilder
    private var trailingActionInfo: some View {
        if let message = vm.lastActionMessage, vm.runningAction == nil {
            Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        Spacer(minLength: 8)
        Button("Close Panel") { NSApp.keyWindow?.orderOut(nil) }
    }

    @ViewBuilder
    private func actionButton(title: String, running: RunningAction, runningTitle: String, action: @escaping () -> Void) -> some View {
        let isRunning = vm.runningAction == running
        Button {
            action()
        } label: {
            HStack(spacing: 5) {
                if isRunning { ProgressView().controlSize(.small) }
                Text(isRunning ? runningTitle : title)
            }
        }
        .disabled(vm.runningAction != nil)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
    }

    private func metricRing(label: String, value: Double, level: MetricLevel) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().stroke(Color.gray.opacity(0.2), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: value)
                    .stroke(color(for: level), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.4), value: value)
                Text("\(Int(value * 100))%").font(.caption2.monospacedDigit())
            }
            .frame(width: 60, height: 60)
            Text(label).font(.caption)
        }
    }

    private func detailRow(icon: String, label: String, value: String, dotColor: Color? = nil) -> some View {
        HStack {
            if let dotColor {
                Circle().fill(dotColor).frame(width: 8, height: 8)
            } else {
                Image(systemName: icon).foregroundStyle(.secondary).frame(width: 14)
            }
            Text(label).font(.system(size: 12))
            Spacer()
            Text(value).font(.system(size: 12).monospacedDigit()).foregroundStyle(.secondary)
        }
    }
}
