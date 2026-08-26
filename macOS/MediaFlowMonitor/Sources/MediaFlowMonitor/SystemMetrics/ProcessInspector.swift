import AppKit
import Darwin
import Foundation

struct ProcessUsage: Identifiable, Equatable {
    let id: Int32 // pid
    let name: String
    let valueGB: Double
}

/// Top consumatori de RAM/Swap per proces.
///
/// IMPORTANT, onest: macOS NU expune public un "swap folosit" per proces —
/// spre deosebire de Windows (PagefileUsage e real). Nu există câmp public
/// în `rusage_info_v4`/`proc_pidinfo` cu octeți efectiv scoși pe disc per
/// proces (nici Activity Monitor nu arată așa ceva). Lista "Swap" de mai
/// jos e deci o aproximare onestă: rangul proceselor după page-in-uri noi
/// (pagini re-aduse din compressor/disk în ultimul interval) — cu cât un
/// proces are mai multe page-ins recente, cu atât SO-ul lucrează mai mult
/// să-i recupereze memoria împinsă afară. Etichetată explicit ca
/// "Swap Activity", nu ca GB static, ca să nu inducă în eroare.
enum ProcessInspector {
    private static var lastPageins: [Int32: UInt64] = [:]
    private static let pageSizeBytes: Double = {
        var size: vm_size_t = 0
        host_page_size(mach_host_self(), &size)
        return Double(size)
    }()

    static func topProcesses(limit: Int = 3) -> (ram: [ProcessUsage], swapActivity: [ProcessUsage]) {
        var pidCount = proc_listallpids(nil, 0)
        guard pidCount > 0 else { return ([], []) }
        var pids = [Int32](repeating: 0, count: Int(pidCount) + 32)
        pidCount = proc_listallpids(&pids, Int32(pids.count) * Int32(MemoryLayout<Int32>.size))

        var ramEntries: [ProcessUsage] = []
        var swapEntries: [ProcessUsage] = []
        var seenThisTick: Set<Int32> = []

        for pid in pids where pid > 0 {
            var info = rusage_info_v4()
            let result = withUnsafeMutablePointer(to: &info) { ptr -> Int32 in
                ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rp in
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, rp)
                }
            }
            guard result == 0 else { continue }
            seenThisTick.insert(pid)

            var nameBuf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            let nameLen = proc_name(pid, &nameBuf, UInt32(nameBuf.count))
            let name = nameLen > 0 ? String(cString: nameBuf) : "pid \(pid)"

            let residentGB = Double(info.ri_phys_footprint) / 1_073_741_824
            if residentGB > 0.01 {
                ramEntries.append(ProcessUsage(id: pid, name: name, valueGB: residentGB))
            }

            let pageins = info.ri_pageins
            let previous = lastPageins[pid] ?? pageins
            let deltaPages = pageins > previous ? pageins - previous : 0
            lastPageins[pid] = pageins
            let deltaMB = Double(deltaPages) * pageSizeBytes / 1_048_576
            if deltaMB > 0.5 {
                swapEntries.append(ProcessUsage(id: pid, name: name, valueGB: deltaMB / 1024))
            }
        }

        // Curăță pid-urile care nu mai există, ca dicționarul să nu crească la infinit.
        lastPageins = lastPageins.filter { seenThisTick.contains($0.key) }

        let topRam = ramEntries.sorted { $0.valueGB > $1.valueGB }.prefix(limit)
        let topSwap = swapEntries.sorted { $0.valueGB > $1.valueGB }.prefix(limit)
        return (Array(topRam), Array(topSwap))
    }

    // MARK: - DaVinci Resolve zombie detection

    /// PID-urile oricărui proces al cărui nume conține "Resolve" — include
    /// procesul principal ȘI helper-ele lui (ex. renderer-e Fusion), care
    /// pot rămâne agățate independent de fereastra principală.
    static func davinciProcessPIDs() -> [Int32] {
        var pidCount = proc_listallpids(nil, 0)
        guard pidCount > 0 else { return [] }
        var pids = [Int32](repeating: 0, count: Int(pidCount) + 32)
        pidCount = proc_listallpids(&pids, Int32(pids.count) * Int32(MemoryLayout<Int32>.size))

        var matches: [Int32] = []
        for pid in pids where pid > 0 {
            var nameBuf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            let len = proc_name(pid, &nameBuf, UInt32(nameBuf.count))
            guard len > 0 else { continue }
            let name = String(cString: nameBuf)
            if name.localizedCaseInsensitiveContains("resolve") {
                matches.append(pid)
            }
        }
        return matches
    }

    /// True dacă DaVinci Resolve apare ca aplicație "lansată" normal (Dock,
    /// Cmd+Tab) — folosit ca să distingem "userul chiar lucrează în Resolve"
    /// de "procesul a rămas agățat după ce fereastra a fost închisă".
    static func isDaVinciResolveAppVisible() -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.localizedName?.localizedCaseInsensitiveContains("davinci resolve") == true
        }
    }

    /// Închide forțat orice proces "Resolve" agățat. Întoarce numărul de
    /// procese omorâte. SIGKILL — deliberat, e exact acțiunea "Force Close".
    @discardableResult
    static func forceKillHangingDaVinci() -> Int {
        let pids = davinciProcessPIDs()
        for pid in pids { kill(pid, SIGKILL) }
        lastPageins = lastPageins.filter { !pids.contains($0.key) }
        return pids.count
    }
}
