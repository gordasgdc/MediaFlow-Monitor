using System;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using Microsoft.Win32;

namespace MediaFlowMonitor.Overlay;

/// Preferintele de comportament ale aplicatiei — oglinda directa a
/// MFMPreferences.swift de pe macOS (Regula 31).
///
/// Registry (HKCU), nu un fisier propriu: sunt trei comutatoare, iar
/// aplicatia nu are deja un store de setari proprii.
public sealed class MFMPreferences : INotifyPropertyChanged
{
    private const string RegistryPath = @"Software\GDC\MediaFlowMonitor";

    public static MFMPreferences Shared { get; } = new MFMPreferences();

    /// Implicit `false`: la prima lansare panoul TREBUIE sa apara. Fara
    /// fereastra si doar cu un icon in tray, un utilizator nou crede ca
    /// aplicatia n-a pornit. Comutatorul e o alegere pe care o face
    /// utilizatorul DUPA ce stie ca aplicatia exista.
    private bool _startMinimized;
    public bool StartMinimized
    {
        get => _startMinimized;
        set { if (Set(ref _startMinimized, value)) Write(nameof(StartMinimized), value); }
    }

    private bool _suppressPurgeWarning;
    public bool SuppressPurgeWarning
    {
        get => _suppressPurgeWarning;
        set { if (Set(ref _suppressPurgeWarning, value)) Write(nameof(SuppressPurgeWarning), value); }
    }

    private bool _suppressOptimiseWarning;
    public bool SuppressOptimiseWarning
    {
        get => _suppressOptimiseWarning;
        set { if (Set(ref _suppressOptimiseWarning, value)) Write(nameof(SuppressOptimiseWarning), value); }
    }

    /// Scurtatura globala, intr-un singur loc — citita din inregistrarea
    /// reala (App.xaml.cs: Control|Shift + 'M'), NU scrisa de mana: un banner
    /// care afiseaza alta combinatie decat cea inregistrata efectiv e mai rau
    /// decat niciun banner. (Cererea initiala mentiona `Alt + Space`;
    /// scurtatura reala a acestei aplicatii e Ctrl+Shift+M.)
    public const string ShortcutDisplay = "Ctrl + Shift + M";
    public const string ShortcutPlainText = "Ctrl + Shift + M";

    private MFMPreferences()
    {
        _startMinimized = Read(nameof(StartMinimized));
        _suppressPurgeWarning = Read(nameof(SuppressPurgeWarning));
        _suppressOptimiseWarning = Read(nameof(SuppressOptimiseWarning));
    }

    private static bool Read(string name)
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(RegistryPath);
            return key?.GetValue(name) is int value && value != 0;
        }
        catch { return false; }
    }

    private static void Write(string name, bool value)
    {
        try
        {
            using var key = Registry.CurrentUser.CreateSubKey(RegistryPath);
            key?.SetValue(name, value ? 1 : 0, RegistryValueKind.DWord);
        }
        catch { /* politica de grup / registry blocat — preferinta ramane doar pe sesiune */ }
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    private bool Set(ref bool field, bool value, [CallerMemberName] string? name = null)
    {
        if (field == value) return false;
        field = value;
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
        return true;
    }
}
