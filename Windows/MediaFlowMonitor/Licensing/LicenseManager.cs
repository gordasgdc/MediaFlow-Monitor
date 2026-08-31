using System;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Threading.Tasks;
using Microsoft.Win32;

namespace MediaFlowMonitor.Licensing;

public enum LicenseKind { Trial, TrialExpired, Licensed }

public readonly record struct LicenseState(LicenseKind Kind, int DaysLeft = 0, long ExpiresAt = 0);

/// Port al LicenseManager.swift — probă gratuită 15 zile (Regula 3), apoi
/// activare prin serial (LicenseCore/Ed25519) generat manual din Furnizor.
/// Persistat în Registry (HKCU), la fel ca ThemeManager/CacheFolderLocator.
public sealed class LicenseManager : INotifyPropertyChanged
{
    public const string ProductID = "media-flow-monitor";
    private const int TrialDays = 15;
    private const string RegistryKey = @"Software\GDC\MediaFlowMonitor";

    public event PropertyChangedEventHandler? PropertyChanged;

    public LicenseState State { get => _state; private set { _state = value; PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(State))); } }
    private LicenseState _state;

    public LicenseManager()
    {
        using (var key = Registry.CurrentUser.CreateSubKey(RegistryKey))
        {
            if (key.GetValue("FirstLaunchDate") == null)
                key.SetValue("FirstLaunchDate", DateTime.UtcNow.ToString("O"));
        }
        Refresh();
        _ = Task.Run(async () =>
        {
            await RevocationCheck.Shared.RefreshAsync(new[] { ProductID });
            Refresh(); // reia decizia locală dacă revocarea tocmai a sosit online
        });
    }

    public void Refresh()
    {
        using var key = Registry.CurrentUser.OpenSubKey(RegistryKey);
        var serial = key?.GetValue("Serial") as string;

        if (!string.IsNullOrEmpty(serial))
        {
            var (payload, error) = LicenseCore.Validate(serial, ProductID);
            if (error == null && payload is { } p && !RevocationCheck.Shared.IsRevoked(ProductID))
            {
                State = new LicenseState(LicenseKind.Licensed, ExpiresAt: p.ExpiresAt);
                return;
            }
        }

        var firstLaunchStr = key?.GetValue("FirstLaunchDate") as string;
        var firstLaunch = DateTime.TryParse(firstLaunchStr, null,
            System.Globalization.DateTimeStyles.RoundtripKind, out var parsed) ? parsed : DateTime.UtcNow;
        int daysUsed = (int)(DateTime.UtcNow - firstLaunch).TotalDays;
        int daysLeft = TrialDays - daysUsed;
        State = daysLeft > 0
            ? new LicenseState(LicenseKind.Trial, DaysLeft: daysLeft)
            : new LicenseState(LicenseKind.TrialExpired);
    }

    /// Activează cu un serial primit de la furnizor (după donație, prin WhatsApp).
    public LicenseCore.ValidationError? Activate(string serial)
    {
        var (_, error) = LicenseCore.Validate(serial, ProductID);
        if (error != null) return error;

        using var key = Registry.CurrentUser.CreateSubKey(RegistryKey);
        key.SetValue("Serial", serial);
        Refresh();
        return null;
    }

    public string MachineIDDisplay => MachineID.Display;

    // Preț dinamic (Regula 27) - vezi PricingChecker. Fail-open pe 7 €
    // (valoarea hardcodata anterior) daca pricing.json nu e accesibil.
    public string WhatsAppActivationUrl
    {
        get
        {
            var priceText = PricingChecker.Shared.DisplayText;
            var text = $"Salut! Vreau Lifetime Access pentru MediaFlow Monitor (donatie {priceText}). Machine ID: {MachineIDDisplay}";
            return $"https://wa.me/34643109970?text={Uri.EscapeDataString(text)}";
        }
    }

    public string StatusText => State.Kind switch
    {
        LicenseKind.Trial => $"Probă gratuită: {State.DaysLeft} zile rămase",
        LicenseKind.TrialExpired => "Probă expirată — activare necesară",
        LicenseKind.Licensed => State.ExpiresAt == 0 ? "Licențiat (Lifetime)" : "Licențiat",
        _ => "",
    };
}
