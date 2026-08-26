import AppKit
import Foundation

/// Verifică `update.json` (găzduit pe gordas.dev, lângă pagina de
/// prezentare) contra versiunii instalate. NU e self-update silențios —
/// deschide link-ul de download, userul instalează manual peste versiunea
/// curentă (Regula 13 din Standardul GDC).
final class UpdateChecker {
    static let shared = UpdateChecker()

    private let updateURL = URL(string: "https://gordas.dev/media-flow-monitor/update.json")!
    private let dismissedKey = "MediaFlowMonitor.dismissedUpdateVersion"

    private struct UpdateInfo: Decodable {
        let version: String
        let changes: String?
        let download_url: [String: String]
        let mandatory: Bool
    }

    func checkAtLaunch() {
        fetch { [weak self] info in
            guard let self, let info else { return }
            guard self.isNewer(info.version) else { return }
            let dismissed = UserDefaults.standard.string(forKey: self.dismissedKey)
            if info.mandatory || dismissed != info.version {
                self.presentPopup(info)
            }
        }
    }

    func checkManually() {
        fetch { [weak self] info in
            guard let self else { return }
            guard let info, self.isNewer(info.version) else {
                self.presentUpToDateAlert()
                return
            }
            self.presentPopup(info)
        }
    }

    private func fetch(completion: @escaping (UpdateInfo?) -> Void) {
        // Cache-buster — GitHub Pages trimite Cache-Control: max-age=14400,
        // altfel un client ar rămâne cu update.json vechi ore întregi.
        var components = URLComponents(url: updateURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "t", value: String(Int(Date().timeIntervalSince1970)))]

        URLSession.shared.dataTask(with: components.url!) { data, _, _ in
            guard let data, let info = try? JSONDecoder().decode(UpdateInfo.self, from: data) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            DispatchQueue.main.async { completion(info) }
        }.resume()
    }

    private func isNewer(_ remote: String) -> Bool {
        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        return remote.compare(current, options: .numeric) == .orderedDescending
    }

    private func presentPopup(_ info: UpdateInfo) {
        let alert = NSAlert()
        alert.messageText = "Versiune nouă disponibilă: \(info.version)"
        alert.informativeText = (info.changes ?? "") + "\n\nTrebuie să descarci pachetul nou și să îl instalezi peste versiunea actuală — nu e o actualizare automată în fundal."
        alert.addButton(withTitle: "Actualizează acum")
        if !info.mandatory {
            alert.addButton(withTitle: "Mai târziu")
        }
        let response = alert.runModal()
        if response == .alertFirstButtonReturn, let urlString = info.download_url["mac"], let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        } else {
            UserDefaults.standard.set(info.version, forKey: dismissedKey)
        }
    }

    private func presentUpToDateAlert() {
        let alert = NSAlert()
        alert.messageText = "Ești la zi"
        alert.informativeText = "Rulezi cea mai recentă versiune."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
