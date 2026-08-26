import AppKit
import Foundation

/// Localizează folderul CacheClip implicit al DaVinci Resolve, pentru
/// alerta de spațiu pe disc și acțiunea "Purge Cache" (deschide în Finder,
/// NU șterge automat — vezi motivul în OverlayViewModel.perform).
enum CacheFolderLocator {
    static var defaultPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Blackmagic Design/DaVinci Resolve/CacheClip")
    }

    /// Spațiu liber (GB) pe discul unde se află CacheClip — pentru Alerta de
    /// Stocare cerută în specificație. Cade grațios pe discul de boot dacă
    /// folderul specific încă nu există (proiect nou, fără cache scris).
    static func freeDiskSpaceGB() -> Double? {
        let path = FileManager.default.fileExists(atPath: defaultPath.path)
            ? defaultPath
            : FileManager.default.homeDirectoryForCurrentUser
        guard let values = try? path.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let bytes = values.volumeAvailableCapacityForImportantUsage else { return nil }
        return Double(bytes) / 1_073_741_824
    }

    static func revealInFinder() {
        let path = FileManager.default.fileExists(atPath: defaultPath.path)
            ? defaultPath
            : defaultPath.deletingLastPathComponent() // fallback: folderul DaVinci Resolve părinte
        NSWorkspace.shared.activateFileViewerSelecting([path])
    }
}
