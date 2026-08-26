import AppKit
import Foundation

struct DiskInfo {
    let path: URL
    let usedGB: Double
    let totalGB: Double
    let freeGB: Double
    /// nil = necunoscut (nu am putut citi SMART/health-ul volumului — normal
    /// pe multe RAID-uri/NVMe externe care nu expun SMART standard prin diskutil).
    let isHealthy: Bool?
}

/// Localizează folderul de cache (CacheClip) al DaVinci Resolve.
///
/// IMPORTANT, onest: DaVinci Resolve NU expune public calea de "Cache
/// Files Location" a proiectului curent (e stocată în baza lui de
/// proiecte — Postgres/SQLite internă, fără API stabil de citire din
/// afară). "Auto-detectarea" de mai jos e deci euristică — verifică
/// locația implicită + scanează volumele montate după un folder numit
/// "CacheClip" — NU citește setarea reală din Resolve. De-asta există
/// obligatoriu și selecția manuală (Regula cerută explicit): un buton
/// de setări care lasă userul să aleagă exact folderul/discul folosit
/// în proiectul curent, salvat persistent.
enum CacheFolderLocator {
    private static let overrideKey = "MediaFlowMonitor.cachePathOverride"
    private static let defaults = UserDefaults.standard

    /// Calea activă: preferința salvată manual de user, dacă există și
    /// tot e validă pe disc — altfel cade pe euristica de auto-detectare.
    static var activePath: URL {
        if let saved = defaults.string(forKey: overrideKey) {
            let url = URL(fileURLWithPath: saved)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return autoDetectedPath
    }

    static var isManualOverride: Bool {
        defaults.string(forKey: overrideKey) != nil
    }

    private static var autoDetectedPath: URL {
        let defaultLocal = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Blackmagic Design/DaVinci Resolve/CacheClip")
        if FileManager.default.fileExists(atPath: defaultLocal.path) { return defaultLocal }

        // Scanează volumele montate (discuri externe Thunderbolt/USB/RAID)
        // după un folder "CacheClip" la primul nivel — pattern comun în
        // workflow-urile profesionale unde cache-ul e mutat pe storage extern.
        if let volumes = try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: "/Volumes"), includingPropertiesForKeys: nil) {
            for volume in volumes {
                let candidate = volume.appendingPathComponent("CacheClip")
                if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            }
        }
        return defaultLocal
    }

    /// Deschide un selector de folder (NSOpenPanel) — Regula cerută explicit:
    /// "posibilitatea de a selecta manual orice folder/disc extern".
    static func chooseFolderManually(completion: @escaping (URL?) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Selectează folderul CacheClip (poate fi pe orice disc extern conectat)"
        panel.directoryURL = URL(fileURLWithPath: "/Volumes")
        panel.begin { response in
            guard response == .OK, let url = panel.url else { completion(nil); return }
            defaults.set(url.path, forKey: overrideKey)
            completion(url)
        }
    }

    static func clearManualOverride() {
        defaults.removeObject(forKey: overrideKey)
    }

    /// Info complet de disc pentru volumul care conține `activePath` —
    /// funcționează identic pentru SSD intern SAU disc extern Thunderbolt
    /// (RAID/DAS/NVMe) — `resourceValues` interoghează volumul montat,
    /// indiferent unde e conectat fizic.
    static func diskInfo() -> DiskInfo? {
        let path = FileManager.default.fileExists(atPath: activePath.path)
            ? activePath
            : FileManager.default.homeDirectoryForCurrentUser

        guard let values = try? path.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeTotalCapacityKey,
        ]) else { return nil }

        guard let totalBytes = values.volumeTotalCapacity else { return nil }
        let freeBytes = values.volumeAvailableCapacityForImportantUsage ?? 0
        let totalGB = Double(totalBytes) / 1_073_741_824
        let freeGB = Double(freeBytes) / 1_073_741_824
        let usedGB = max(totalGB - freeGB, 0)

        return DiskInfo(path: path, usedGB: usedGB, totalGB: totalGB, freeGB: freeGB, isHealthy: volumeHealth(for: path))
    }

    /// Best-effort: `diskutil info` e read-only (nicio scriere, nicio
    /// modificare) — citește "SMART Status" dacă volumul îl expune.
    /// Multe RAID-uri/adaptoare Thunderbolt NU expun SMART standard —
    /// în acel caz întoarce nil (necunoscut), nu fals-pozitiv.
    private static func volumeHealth(for path: URL) -> Bool? {
        guard let mountPoint = (try? path.resourceValues(forKeys: [.volumeURLKey]))?.volume?.path else { return nil }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        task.arguments = ["info", mountPoint]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        guard (try? task.run()) != nil else { return nil }
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }
        if output.contains("SMART Status:              Verified") { return true }
        if output.contains("SMART Status:              Failing") { return false }
        return nil
    }

    static func revealInFinder() {
        let path = FileManager.default.fileExists(atPath: activePath.path)
            ? activePath
            : activePath.deletingLastPathComponent()
        NSWorkspace.shared.activateFileViewerSelecting([path])
    }

    /// Purge REAL — șterge conținutul folderului CacheClip activ (extern
    /// sau local). Apelantul TREBUIE să confirme cu userul înainte
    /// (NSAlert) — funcția asta doar execută, nu cere confirmare ea
    /// însăși, ca să rămână testabilă/reutilizabilă.
    static func purge() throws -> Int {
        let path = activePath
        guard FileManager.default.fileExists(atPath: path.path) else { return 0 }
        let contents = try FileManager.default.contentsOfDirectory(at: path, includingPropertiesForKeys: nil)
        for item in contents {
            try FileManager.default.removeItem(at: item)
        }
        return contents.count
    }
}
