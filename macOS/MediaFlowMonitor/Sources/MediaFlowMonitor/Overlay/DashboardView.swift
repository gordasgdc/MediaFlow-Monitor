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
            "Golește tot conținutul din \(CacheFolderLocator.activePath.path)?",
            isPresented: $showPurgeConfirm, titleVisibility: .visible
        ) {
            Button("Golește Cache", role: .destructive) {
                // Confirmarea a avut deja loc prin acest confirmationDialog —
                // callback-ul de aprobare din requestPurgeCache primeste `true` direct.
                vm.requestPurgeCache { callback in callback(true) }
            }
            Button("Anulează", role: .cancel) {}
        }
        .sheet(isPresented: $vm.showActionConsole) {
            actionConsoleSheet
        }
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
                Circle().fill(color(for: vm.overallLevel)).frame(width: 10, height: 10)
            }
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
            showPurgeConfirm = true
        }
        actionButton(title: "Force Sync Log", running: .forceSyncLog, runningTitle: "Syncing…") {
            vm.forceSyncLog()
        }
        actionButton(title: "Optimise System", running: .optimiseSystem, runningTitle: "Optimising…") {
            vm.optimiseSystem()
        }
        Button("Copy Diagnostics") { vm.copyDiagnosticsToClipboard() }
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
