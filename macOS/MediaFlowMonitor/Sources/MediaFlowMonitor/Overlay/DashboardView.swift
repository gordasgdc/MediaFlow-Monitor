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

    var body: some View {
        VStack(spacing: 14) {
            topBar
            healthRow
            performanceSection
            HStack(alignment: .top, spacing: 14) {
                logDecoderPanel
                recommendationsPanel
            }
            cacheDiskPanel
            actionBar
        }
        .padding(16)
        .frame(minWidth: 620, maxWidth: .infinity, minHeight: 560, maxHeight: .infinity)
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
        HStack {
            Text("MediaFlow Monitor").font(.headline)
            Spacer()
            Picker("Temă", selection: Binding(
                get: { ThemeManager.shared.current },
                set: { ThemeManager.shared.set($0) }
            )) {
                ForEach(AppTheme.allCases, id: \.self) { theme in
                    Text(theme.label).tag(theme)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
        }
    }

    // MARK: - System Health

    private var healthRow: some View {
        HStack(spacing: 14) {
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
            }
            card {
                HStack {
                    Text("System Health").font(.headline)
                    Spacer()
                    Circle().fill(color(for: vm.overallLevel)).frame(width: 10, height: 10)
                }
                VStack(alignment: .leading, spacing: 6) {
                    detailRow(icon: "cpu", label: "VRAM", value: vm.vramUsedGB.map { String(format: "%.1f GB", $0) } ?? "—")
                    detailRow(icon: "internaldrive", label: "Partition", value: vm.diskInfo.map { String(format: "%.0f GB", $0.totalGB) } ?? "—")
                    detailRow(icon: "circle.fill", label: "CacheClip disk", value: vm.diskInfo.map { String(format: "%.0f GB liber", $0.freeGB) } ?? "—", dotColor: diskDotColor)
                }
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
            HStack(spacing: 16) {
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
                }
            }
        }
    }

    // MARK: - Log decoder

    private var logDecoderPanel: some View {
        card {
            HStack {
                Text("Real-time Log Decoder").font(.headline)
                Spacer()
                Button { vm.forceSyncLog() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    if vm.logConsole.isEmpty {
                        Text("Niciun eveniment încă — se ascultă log-ul DaVinci Resolve...")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(vm.logConsole) { entry in
                        Text("\(entry.date.formatted(date: .omitted, time: .standard))  \(entry.text)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(color(for: entry.level))
                    }
                }
            }
            .frame(height: 160)
        }
        .frame(maxWidth: .infinity)
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
        .frame(width: 260, alignment: .topLeading)
    }

    // MARK: - Cache disk detail

    private var cacheDiskPanel: some View {
        card {
            HStack {
                Text("CacheClip disk").font(.headline)
                Spacer()
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
        HStack {
            actionButton(title: "Purge Cache", running: .purgeCache, runningTitle: "Purging…") {
                showPurgeConfirm = true
            }
            actionButton(title: "Force Sync Log", running: .forceSyncLog, runningTitle: "Syncing…") {
                vm.forceSyncLog()
            }
            actionButton(title: "Optimise System", running: .optimiseSystem, runningTitle: "Optimising…") {
                vm.optimiseSystem()
            }
            if vm.runningAction != nil {
                Button("Vezi log") { vm.showActionConsole = true }
                    .buttonStyle(.link).font(.caption)
            }
            Spacer()
            if let message = vm.lastActionMessage, vm.runningAction == nil {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            Button("Close Panel") { NSApp.keyWindow?.orderOut(nil) }
        }
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
