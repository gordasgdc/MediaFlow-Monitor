import Foundation

/// Stare de licențiere: probă gratuită 15 zile (Regula 3), apoi activare
/// prin serial (LicenseCore/Ed25519) generat manual din Furnizor.
/// Susținerea aplicației e o DONAȚIE, niciodată "preț"/"cumpără"/"vânzare".
enum LicenseState: Equatable {
    case trial(daysLeft: Int)
    case trialExpired
    case licensed(expiresAt: Int64) // 0 = lifetime
}

final class LicenseManager: ObservableObject {
    static let productID = "media-flow-monitor"
    private static let trialDays = 15

    @Published private(set) var state: LicenseState = .trial(daysLeft: LicenseManager.trialDays)

    private let defaults = UserDefaults.standard
    private let firstLaunchKey = "MediaFlowMonitor.firstLaunchDate"
    private let serialKey = "MediaFlowMonitor.serial"

    init() {
        if defaults.object(forKey: firstLaunchKey) == nil {
            defaults.set(Date(), forKey: firstLaunchKey)
        }
        refresh()
        Task {
            await RevocationCheck.shared.refresh(productIDs: [Self.productID])
            refresh() // reia decizia locală dacă revocarea tocmai a sosit online
        }
    }

    func refresh() {
        if let serial = defaults.string(forKey: serialKey),
           case .success(let payload) = LicenseCore.validate(serial: serial, expectedProductID: Self.productID),
           !RevocationCheck.shared.isRevoked(Self.productID) {
            state = .licensed(expiresAt: payload.expiresAt)
            return
        }

        let firstLaunch = defaults.object(forKey: firstLaunchKey) as? Date ?? Date()
        let daysUsed = Calendar.current.dateComponents([.day], from: firstLaunch, to: Date()).day ?? 0
        let daysLeft = Self.trialDays - daysUsed
        state = daysLeft > 0 ? .trial(daysLeft: daysLeft) : .trialExpired
    }

    /// Activează cu un serial primit de la furnizor (după donație, prin WhatsApp).
    func activate(serial: String) -> Result<Void, LicenseCore.ValidationError> {
        switch LicenseCore.validate(serial: serial, expectedProductID: Self.productID) {
        case .success:
            defaults.set(serial, forKey: serialKey)
            refresh()
            return .success(())
        case .failure(let error):
            return .failure(error)
        }
    }

    var machineIDDisplay: String { MachineID.display }

    var whatsAppActivationURL: URL {
        let text = "Salut! Vreau Lifetime Access pentru MediaFlow Monitor (donatie 7e). Machine ID: \(machineIDDisplay)"
        let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
        return URL(string: "https://wa.me/34643109970?text=\(encoded)")!
    }
}
