import Foundation
import Darwin

/// Citește utilizarea CPU per-thread/core, via `host_processor_info`
/// (Mach) — aceeași familie de API ca `SystemMetrics.readRAM()`, fără
/// subprocese (`top`/`ps`).
enum CPUMonitor {
    private static var previousTicks: [[UInt32]] = []

    /// Întoarce fracția de utilizare (0...1) per core, comparând ticks-urile
    /// curente cu cele de la apelul anterior — primul apel întoarce zero
    /// pentru toate (nu există un "înainte" de comparat).
    static func perCoreUsage() -> [Double] {
        var numCPUsU: natural_t = 0
        var cpuInfo: processor_info_array_t!
        var numCpuInfo: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
            &numCPUsU, &cpuInfo, &numCpuInfo
        )
        guard result == KERN_SUCCESS, let cpuInfo else { return [] }
        defer {
            let size = vm_size_t(numCpuInfo) * vm_size_t(MemoryLayout<integer_t>.size)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), size)
        }

        let numCPUs = Int(numCPUsU)
        var currentTicks: [[UInt32]] = []
        for i in 0..<numCPUs {
            let base = i * Int(CPU_STATE_MAX)
            let user = cpuInfo[base + Int(CPU_STATE_USER)]
            let system = cpuInfo[base + Int(CPU_STATE_SYSTEM)]
            let nice = cpuInfo[base + Int(CPU_STATE_NICE)]
            let idle = cpuInfo[base + Int(CPU_STATE_IDLE)]
            currentTicks.append([UInt32(user), UInt32(system), UInt32(nice), UInt32(idle)])
        }

        defer { previousTicks = currentTicks }
        guard previousTicks.count == currentTicks.count else {
            return Array(repeating: 0, count: numCPUs)
        }

        return zip(previousTicks, currentTicks).map { prev, curr in
            let usedPrev = prev[0] + prev[1] + prev[2]
            let usedCurr = curr[0] + curr[1] + curr[2]
            let totalPrev = usedPrev + prev[3]
            let totalCurr = usedCurr + curr[3]
            let usedDelta = Double(usedCurr &- usedPrev)
            let totalDelta = Double(totalCurr &- totalPrev)
            guard totalDelta > 0 else { return 0 }
            return min(max(usedDelta / totalDelta, 0), 1)
        }
    }
}
