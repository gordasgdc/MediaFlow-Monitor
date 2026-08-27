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

    /// BUG REAL găsit 2026-08-26: `fetch` întorcea `nil` la orice eșec
    /// (rețea, timeout, JSON invalid) — `checkManually()` trata `nil`
    /// IDENTIC cu "nu există versiune nouă", deci un simplu hiccup de
    /// rețea (sau propagare încă neterminată pe GitHub Pages/Fastly chiar
    /// după un push) făcea aplicația să mintă userul cu "Ești la zi", deși
    /// era deja live o versiune nouă. Fix: `fetch` întoarce acum
    /// `Result<UpdateInfo, Error>` — eșecul e arătat explicit ca eroare,
    /// niciodată deghizat în "la zi".
    private enum FetchError: Error, LocalizedError {
        case network(Error)
        case badStatus(Int)
        case decode(Error)

        var errorDescription: String? {
            switch self {
            case .network(let e): return e.localizedDescription
            case .badStatus(let code): return "Server a răspuns cu status \(code)."
            case .decode: return "Răspunsul primit nu e un update.json valid."
            }
        }
    }

    func checkAtLaunch() {
        fetch { [weak self] result in
            guard let self, case .success(let info) = result else { return }
            guard self.isNewer(info.version) else { return }
            let dismissed = UserDefaults.standard.string(forKey: self.dismissedKey)
            if info.mandatory || dismissed != info.version {
                self.presentPopup(info)
            }
        }
    }

    func checkManually() {
        fetch { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.presentCheckFailedAlert(error)
            case .success(let info):
                if self.isNewer(info.version) {
                    self.presentPopup(info)
                } else {
                    self.presentUpToDateAlert()
                }
            }
        }
    }

    private func fetch(completion: @escaping (Result<UpdateInfo, Error>) -> Void) {
        // Dublu cache-bypass: (1) query param unic per cerere — necesar
        // pentru CDN-urile din față (GitHub Pages/Fastly, Cloudflare) care
        // cache-uiesc pe URL complet; (2) cachePolicy explicit pe
        // URLRequest — necesar ca NICI URLCache-ul local (in-process) să nu
        // servească un răspuns anterior, indiferent de Cache-Control primit.
        var components = URLComponents(url: updateURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "t", value: String(Int(Date().timeIntervalSince1970)))]

        var request = URLRequest(url: components.url!)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                DispatchQueue.main.async { completion(.failure(FetchError.network(error))) }
                return
            }
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                DispatchQueue.main.async { completion(.failure(FetchError.badStatus(http.statusCode))) }
                return
            }
            guard let data else {
                DispatchQueue.main.async { completion(.failure(FetchError.badStatus(-1))) }
                return
            }
            do {
                let info = try JSONDecoder().decode(UpdateInfo.self, from: data)
                DispatchQueue.main.async { completion(.success(info)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(FetchError.decode(error))) }
            }
        }.resume()
    }

    /// Comparare SemVer robustă, component cu component (Major.Minor.Patch)
    /// — înlocuiește `String.compare(_:options:.numeric)`, care se poate
    /// comporta imprevizibil dacă una din cele două valori are un prefix
    /// „v” și cealaltă nu (ex. „v1.5.0” vs „1.4.0”: primul caracter „v” vs
    /// „1” e comparat lexical, ÎNAINTE de orice comparație numerică).
    /// Ignoră explicit un eventual prefix „v”/„V”.
    private func isNewer(_ remote: String) -> Bool {
        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        return Self.semVerCompare(remote, current) > 0
    }

    /// Întoarce 1 dacă `a` > `b`, -1 dacă `a` < `b`, 0 dacă egale.
    /// Componente lipsă/nenumerice se tratează ca 0 — niciodată crash.
    static func semVerCompare(_ a: String, _ b: String) -> Int {
        func parts(_ s: String) -> [Int] {
            var s = s
            if s.lowercased().hasPrefix("v") { s.removeFirst() }
            return s.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        }
        let pa = parts(a), pb = parts(b)
        for i in 0..<max(pa.count, pb.count) {
            let va = i < pa.count ? pa[i] : 0
            let vb = i < pb.count ? pb[i] : 0
            if va != vb { return va > vb ? 1 : -1 }
        }
        return 0
    }

    /// BUG FIX 2026-08-27 (CLAUDE.md Partea 1, Regula 20): butonul
    /// "Actualizează acum" deschidea `.pkg`-ul în browser (fișier descărcat,
    /// dar userul tot vedea un tab de download) — acum descarcă+instalează
    /// direct, prin SelfUpdater, fără NICIODATĂ să atingă un browser.
    private func presentPopup(_ info: UpdateInfo) {
        let alert = NSAlert()
        alert.messageText = "Versiune nouă disponibilă: \(info.version)"
        alert.informativeText = (info.changes ?? "") + "\n\nApasă „Actualizează acum” pentru a descărca și instala automat."
        alert.addButton(withTitle: "Actualizează acum")
        if !info.mandatory {
            alert.addButton(withTitle: "Mai târziu")
        }
        let response = alert.runModal()
        if response == .alertFirstButtonReturn, let urlString = info.download_url["mac"], let url = URL(string: urlString) {
            Task { await SelfUpdater.downloadAndInstall(pkgURL: url, version: info.version) }
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

    /// Distinct explicit de "Ești la zi" — un eșec de rețea/parsing NU
    /// înseamnă că nu există versiune nouă, doar că n-am putut verifica.
    private func presentCheckFailedAlert(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Nu am putut verifica actualizări"
        alert.informativeText = "\(error.localizedDescription)\n\nVerifică-ți conexiunea la internet și încearcă din nou, sau vizitează direct gordas.dev/media-flow-monitor."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
