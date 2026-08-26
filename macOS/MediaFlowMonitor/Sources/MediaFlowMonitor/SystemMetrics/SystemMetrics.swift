import Foundation
import Combine
import Darwin
import Darwin.Mach

/// Nivel de alertă pentru semafor vizual (Verde/Galben/Roșu).
enum MetricLevel { case ok, warning, critical }

struct MemorySnapshot: Equatable {
    let ramUsedGB: Double
    let ramTotalGB: Double
    let swapUsedGB: Double
    let swapLevel: MetricLevel
    let vramUsedGB: Double?
    let cpuPerCore: [Double]
}

/// Citește RAM + Swap + (opțional) VRAM la interval adaptiv, fără polling agresiv.
/// Cost: apeluri Mach/sysctl directe, fără subprocese, fără Task/Process.
final class SystemMetrics {

    let snapshotPublisher = CurrentValueSubject<MemorySnapshot?, Never>(nil)

    private var timer: DispatchSourceTimer?
    private var lastSwapUsed: Double = 0
    private let idleInterval: TimeInterval = 3.0
    private let activeInterval: TimeInterval = 1.0
    var isTimelineActive: Bool = false {
        didSet { if isTimelineActive != oldValue { restart() } }
    }

    func start() { restart() }

    private func restart() {
        timer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "mediaflow.sysmetrics", qos: .utility))
        let interval = isTimelineActive ? activeInterval : idleInterval
        t.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(500))
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    func stop() { timer?.cancel(); timer = nil }

    private func tick() {
        guard let ram = Self.readRAM(), let swap = Self.readSwap() else { return }
        let swapDelta = swap - lastSwapUsed
        lastSwapUsed = swap

        let level: MetricLevel
        if swap > 4.0 || swapDelta > 0.5 { level = .critical }
        else if swap > 1.0 || swapDelta > 0.1 { level = .warning }
        else { level = .ok }

        snapshotPublisher.send(MemorySnapshot(
            ramUsedGB: ram.used, ramTotalGB: ram.total,
            swapUsedGB: swap, swapLevel: level,
            vramUsedGB: VRAMProbe.readUsedGB(),
            cpuPerCore: CPUMonitor.perCoreUsage()
        ))
    }

    // MARK: - RAM (host_statistics64)

    private static func readRAM() -> (used: Double, total: Double)? {
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let used = Double(stats.active_count + stats.wire_count + stats.compressor_page_count) * Double(pageSize)
        var totalMem: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &totalMem, &size, nil, 0)

        return (used / 1_073_741_824, Double(totalMem) / 1_073_741_824)
    }

    // MARK: - Swap (sysctl vm.swapusage)

    private static func readSwap() -> Double? {
        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 else { return nil }
        return Double(swap.xsu_used) / 1_073_741_824
    }
}
