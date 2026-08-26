import Foundation

/// Port byte-for-byte din gdc-plugin-manager-catalog-vendor
/// (RevocationCheck.swift) — apelează RPC-ul `is_license_revoked`, deja
/// live în Supabase (funcție generică, orice `product_id`). FAIL-OPEN:
/// fără conexiune, licența deja activată local continuă să funcționeze.
final class RevocationCheck: @unchecked Sendable {
    static let shared = RevocationCheck()

    private let lock = NSLock()
    private var _revokedProductIDs: Set<String> = []
    var revokedProductIDs: Set<String> {
        lock.lock(); defer { lock.unlock() }
        return _revokedProductIDs
    }

    private init() {}

    func isRevoked(_ productID: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return _revokedProductIDs.contains(productID)
    }

    private func markRevoked(_ productID: String) {
        lock.lock(); defer { lock.unlock() }
        _revokedProductIDs.insert(productID)
    }

    func refresh(productIDs: [String]) async {
        for productID in productIDs {
            if let revoked = await checkOne(machineID: MachineID.display, productID: productID), revoked {
                markRevoked(productID)
            }
        }
    }

    private func checkOne(machineID: String, productID: String) async -> Bool? {
        guard SupabaseConfig.projectURL.hasPrefix("https://") else { return nil }
        let url = URL(string: SupabaseConfig.projectURL)!.appendingPathComponent("rest/v1/rpc/is_license_revoked")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        let body: [String: String] = ["p_machine_id": machineID, "p_product_id": productID]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        request.httpBody = data
        request.timeoutInterval = 8

        guard let (respData, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return nil // orice eroare de rețea/server -> fail-open, NU revocat
        }
        if let text = String(data: respData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
            return text == "true"
        }
        return nil
    }
}
