using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Linq;
using System.Net.Http;
using System.Net.Http.Json;
using System.Text.Json.Serialization;
using System.Threading.Tasks;

namespace MediaFlowMonitor.Licensing;

/// Preț dinamic (Regula 27, portat 2026-08-31 din DataMover/Mac) — citește
/// `pricing.json` (Furnizor, `gdc-plugin-manager-catalog-vendor`, servit
/// static la `https://gordas.dev/pricing.json`) în loc de suma hardcodată
/// din `LicenseManager.WhatsAppActivationUrl`. Fail-open: fără conexiune
/// sau `productID` lipsă, se folosește `FallbackBasePrice` (7 €, valoarea
/// hardcodată anterior).
public sealed class PricingChecker : INotifyPropertyChanged
{
    public static readonly PricingChecker Shared = new();

    private const string PricingUrl = "https://gordas.dev/pricing.json";
    private const string ProductID = "media-flow-monitor";
    public const double FallbackBasePrice = 7;

    public event PropertyChangedEventHandler? PropertyChanged;

    public double BasePrice { get; private set; } = FallbackBasePrice;
    public PricingPromo? ActivePromo { get; private set; }

    public double EffectivePrice => ActivePromo?.Price ?? BasePrice;

    public string DisplayText => ActivePromo is { } promo
        ? $"{FormatPrice(promo.Price)} (în loc de {FormatPrice(BasePrice)})"
        : FormatPrice(EffectivePrice);

    private static string FormatPrice(double value)
    {
        var isWhole = value % 1 == 0;
        return $"{(isWhole ? ((long)value).ToString() : value.ToString())} €";
    }

    private sealed class PricingCatalog
    {
        [JsonPropertyName("products")]
        public Dictionary<string, ProductPricing> Products { get; set; } = new();
    }

    private sealed class ProductPricing
    {
        [JsonPropertyName("basePrice")]
        public double BasePrice { get; set; }
        [JsonPropertyName("promoSchedule")]
        public List<PricingPromo> PromoSchedule { get; set; } = new();
    }

    public sealed class PricingPromo
    {
        [JsonPropertyName("price")]
        public double Price { get; set; }
        [JsonPropertyName("label")]
        public string Label { get; set; } = "";
        [JsonPropertyName("startsAt")]
        public DateTimeOffset StartsAt { get; set; }
        [JsonPropertyName("endsAt")]
        public DateTimeOffset EndsAt { get; set; }
        [JsonPropertyName("showCountdown")]
        public bool ShowCountdown { get; set; }

        public bool IsActiveNow
        {
            get
            {
                var now = DateTimeOffset.UtcNow;
                return now >= StartsAt && now <= EndsAt;
            }
        }
    }

    private PricingChecker() { _ = RefreshAsync(); }

    public async Task RefreshAsync()
    {
        try
        {
            using var client = new HttpClient();
            client.DefaultRequestHeaders.UserAgent.ParseAdd("MediaFlowMonitor");
            var response = await client.GetAsync(PricingUrl);
            if (!response.IsSuccessStatusCode) return;
            var catalog = await response.Content.ReadFromJsonAsync<PricingCatalog>();
            if (catalog == null || !catalog.Products.TryGetValue(ProductID, out var product)) return;

            BasePrice = product.BasePrice;
            ActivePromo = product.PromoSchedule.FirstOrDefault(p => p.IsActiveNow);
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(BasePrice)));
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(ActivePromo)));
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(DisplayText)));
        }
        catch
        {
            // Fail-open: rămâne pe FallbackBasePrice/BasePrice deja setat.
        }
    }
}
