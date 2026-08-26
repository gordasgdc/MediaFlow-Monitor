import Foundation
import IOKit

/// Citește memoria GPU folosită, via IOKit (`IOAccelerator`/`AGXAccelerator`
/// pe Apple Silicon — memorie unificată, deci "VRAM" e un subset din RAM).
/// Cheile din PerformanceStatistics sunt PRIVATE/nedocumentate de Apple —
/// best-effort: dacă nu le găsește, întoarce nil (degradare grațioasă,
/// niciodată crash).
enum VRAMProbe {
    static func readUsedBytes() -> UInt64? {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOAccelerator")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service); service = IOIteratorNext(iterator) }

            guard let props = IORegistryEntryCreateCFProperty(
                service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? [String: Any] else { continue }

            // Chei observate empiric pe Apple Silicon (pot varia între versiuni macOS).
            for key in ["In use system memory", "Alloc system memory", "vramUsedBytes"] {
                if let value = props[key] as? NSNumber {
                    return value.uint64Value
                }
            }
        }
        return nil
    }

    static func readUsedGB() -> Double? {
        guard let bytes = readUsedBytes() else { return nil }
        return Double(bytes) / 1_073_741_824
    }
}
