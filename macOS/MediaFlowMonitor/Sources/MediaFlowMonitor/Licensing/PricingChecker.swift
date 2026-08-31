import Foundation
import Combine

/// Preț dinamic (Regula 27, portat 2026-08-31 din DataMover) — citește
/// `pricing.json` (Furnizor, `gdc-plugin-manager-catalog-vendor`, servit
/// static la `https://gordas.dev/pricing.json`) în loc de suma hardcodată
/// din `LicenseManager.whatsAppActivationURL`. Fail-open: fără conexiune
/// sau `productID` lipsă, se folosește `fallbackBasePrice` (7 €, valoarea
/// hardcodată anterior).
final class PricingChecker: ObservableObject {
    static let shared = PricingChecker()

    private static let pricingURL = URL(string: "https://gordas.dev/pricing.json")!
    private static let productID = "media-flow-monitor"
    static let fallbackBasePrice: Double = 7

    @Published private(set) var basePrice: Double = fallbackBasePrice
    @Published private(set) var activePromo: PricingPromo?

    var effectivePrice: Double { activePromo?.price ?? basePrice }

    var displayText: String {
        if let promo = activePromo {
            return "\(formattedPrice(promo.price)) (în loc de \(formattedPrice(basePrice)))"
        }
        return formattedPrice(effectivePrice)
    }

    private func formattedPrice(_ value: Double) -> String {
        let isWhole = value.truncatingRemainder(dividingBy: 1) == 0
        return "\(isWhole ? String(Int(value)) : String(value)) €"
    }

    private struct PricingCatalog: Codable {
        var products: [String: ProductPricing]
    }
    private struct ProductPricing: Codable {
        var basePrice: Double
        var promoSchedule: [PricingPromo] = []

        enum CodingKeys: String, CodingKey { case basePrice, promoSchedule }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            basePrice = try c.decode(Double.self, forKey: .basePrice)
            promoSchedule = try c.decodeIfPresent([PricingPromo].self, forKey: .promoSchedule) ?? []
        }
    }

    struct PricingPromo: Codable {
        var price: Double
        var label: String
        var startsAt: Date
        var endsAt: Date
        var showCountdown: Bool = false

        enum CodingKeys: String, CodingKey { case price, label, startsAt, endsAt, showCountdown }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            price = try c.decode(Double.self, forKey: .price)
            label = try c.decode(String.self, forKey: .label)
            startsAt = try c.decode(Date.self, forKey: .startsAt)
            endsAt = try c.decode(Date.self, forKey: .endsAt)
            showCountdown = try c.decodeIfPresent(Bool.self, forKey: .showCountdown) ?? false
        }

        var isActiveNow: Bool {
            let now = Date()
            return now >= startsAt && now <= endsAt
        }
    }

    private init() {
        refresh()
    }

    func refresh() {
        let task = URLSession.shared.dataTask(with: Self.pricingURL) { [weak self] data, response, error in
            guard let self, error == nil,
                  let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let data else { return }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard let catalog = try? decoder.decode(PricingCatalog.self, from: data),
                  let product = catalog.products[Self.productID] else { return }
            DispatchQueue.main.async {
                self.basePrice = product.basePrice
                self.activePromo = product.promoSchedule.first(where: { $0.isActiveNow })
            }
        }
        task.resume()
    }
}
