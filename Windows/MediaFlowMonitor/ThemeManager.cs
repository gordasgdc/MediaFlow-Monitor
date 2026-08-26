using System;
using System.Windows;
using Microsoft.Win32;

namespace MediaFlowMonitor;

public enum AppTheme { System, Light, Dark }

/// Selector explicit System/Dark/Light, independent de setarea Windows —
/// echivalentul AppTheme.swift/ThemeManager de pe Mac (Regula 18, CLAUDE.md).
/// Persistat în Registry (HKCU), aplicat imediat prin swap de
/// ResourceDictionary — nu necesită repornirea aplicației.
public sealed class ThemeManager
{
    public static readonly ThemeManager Shared = new();

    private const string RegistryKey = @"Software\GDC\MediaFlowMonitor";
    private const string ValueName = "AppTheme";

    public event EventHandler? ThemeChanged;

    private AppTheme _current;
    public AppTheme Current
    {
        get => _current;
        private set { _current = value; Apply(); ThemeChanged?.Invoke(this, EventArgs.Empty); }
    }

    private ThemeManager()
    {
        using var key = Registry.CurrentUser.OpenSubKey(RegistryKey);
        var saved = key?.GetValue(ValueName) as string;
        _current = Enum.TryParse<AppTheme>(saved, out var theme) ? theme : AppTheme.System;
        Apply();
        SystemEvents.UserPreferenceChanged += (_, e) =>
        {
            if (e.Category == UserPreferenceCategory.General && _current == AppTheme.System)
                Apply();
        };
    }

    public void Set(AppTheme theme)
    {
        using var key = Registry.CurrentUser.CreateSubKey(RegistryKey);
        key.SetValue(ValueName, theme.ToString());
        Current = theme;
    }

    private void Apply()
    {
        bool isDark = _current switch
        {
            AppTheme.Dark => true,
            AppTheme.Light => false,
            _ => IsSystemInDarkMode(),
        };

        // Pack URI absolut, nu relativ — setat din C# (nu din XAML), un URI
        // relativ nu are garantat un "site of origin" de rezolvat și poate
        // arunca "Cannot locate resource" în funcție de contextul apelant.
        var uri = new Uri(isDark
            ? "pack://application:,,,/Themes/DarkTheme.xaml"
            : "pack://application:,,,/Themes/LightTheme.xaml", UriKind.Absolute);
        var dict = new ResourceDictionary { Source = uri };

        var app = Application.Current;
        if (app == null) return;
        // Scoate orice temă aplicată anterior (identificată după conținutul
        // "Themes/" din sursă), apoi adaugă noua — evită acumularea de
        // dicționare vechi la fiecare comutare.
        for (int i = app.Resources.MergedDictionaries.Count - 1; i >= 0; i--)
        {
            var existing = app.Resources.MergedDictionaries[i];
            if (existing.Source?.OriginalString.Contains("Themes/") == true)
                app.Resources.MergedDictionaries.RemoveAt(i);
        }
        app.Resources.MergedDictionaries.Add(dict);
    }

    private static bool IsSystemInDarkMode()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(
                @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            var value = key?.GetValue("AppsUseLightTheme");
            return value is int i && i == 0;
        }
        catch { return false; }
    }
}
