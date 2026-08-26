using System;
using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Forms;
using MediaFlowMonitor.LogEngine;
using MediaFlowMonitor.Licensing;
using MediaFlowMonitor.SystemMetrics;
using MediaFlowMonitor.Overlay;
using Application = System.Windows.Application;

namespace MediaFlowMonitor;

/// Entry point WPF — fara fereastra principala vizibila, doar tray icon + overlay.
public partial class App : Application
{
    private DaVinciLogWatcher? _logWatcher;
    private SystemMetricsMonitor? _metrics;
    private OverlayWindow? _overlay;
    private GlobalHotkey? _hotkey;
    private NotifyIcon? _trayIcon;
    private LicenseManager? _license;
    private ToolStripMenuItem? _licenseStatusItem;

    private static readonly string CrashLogPath = Path.Combine(Path.GetTempPath(), "MediaFlowMonitor-crash.log");

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        AppDomain.CurrentDomain.UnhandledException += (_, ev) =>
            LogCrash("AppDomain.UnhandledException", ev.ExceptionObject as Exception);
        DispatcherUnhandledException += (_, ev) =>
        {
            LogCrash("DispatcherUnhandledException", ev.Exception);
            ev.Handled = true;
        };

        try
        {
            _metrics = new SystemMetricsMonitor();
            _metrics.Start();

            _logWatcher = new DaVinciLogWatcher();
            _logWatcher.Start();

            _overlay = new OverlayWindow(_metrics, _logWatcher);

            _license = new LicenseManager();
            _license.PropertyChanged += (_, _) => Dispatcher.Invoke(RefreshLicenseMenuText);

            SetupTrayIcon();

            _hotkey = new GlobalHotkey(modifiers: HotkeyModifiers.Control | HotkeyModifiers.Shift, key: 0x4D /* 'M' */);
            _hotkey.Pressed += (_, _) => _overlay.Toggle();
        }
        catch (Exception ex)
        {
            LogCrash("OnStartup", ex);
            throw;
        }
    }

    private void SetupTrayIcon()
    {
        var menu = new ContextMenuStrip();
        menu.Items.Add("Arata/Ascunde panoul (Ctrl+Shift+M)", null, (_, _) => _overlay?.Toggle());
        menu.Items.Add(new ToolStripSeparator());

        _licenseStatusItem = new ToolStripMenuItem(_license?.StatusText ?? "") { Enabled = false };
        menu.Items.Add(_licenseStatusItem);
        menu.Items.Add($"Machine ID: {_license?.MachineIDDisplay}", null, (_, _) => CopyMachineID());
        menu.Items.Add("Activeaza licenta (WhatsApp)...", null, (_, _) => OpenWhatsAppActivation());
        menu.Items.Add("Introdu codul de activare...", null, (_, _) => PromptActivationCode());
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Iesire", null, (_, _) => Shutdown());

        _trayIcon = new NotifyIcon
        {
            Icon = LoadAppIcon(),
            Visible = true,
            Text = "MediaFlow Monitor",
            ContextMenuStrip = menu,
        };
        _trayIcon.DoubleClick += (_, _) => _overlay?.Toggle();
    }

    /// BUG FIX (2026-08-26): tray icon-ul folosea `SystemIcons.Application`
    /// (iconița generică Windows) — `build-windows-exe.ps1` copiază deja
    /// `Resources\GDC\gdc-icon.ico` lângă executabil, doar nu era citit.
    private static System.Drawing.Icon LoadAppIcon()
    {
        try
        {
            var path = Path.Combine(AppContext.BaseDirectory, "Resources", "GDC", "gdc-icon.ico");
            if (File.Exists(path)) return new System.Drawing.Icon(path);
        }
        catch { /* fallback mai jos */ }
        return System.Drawing.SystemIcons.Application;
    }

    private void RefreshLicenseMenuText()
    {
        if (_licenseStatusItem != null && _license != null)
            _licenseStatusItem.Text = _license.StatusText;
    }

    private void CopyMachineID()
    {
        if (_license == null) return;
        System.Windows.Clipboard.SetText(_license.MachineIDDisplay);
    }

    private void OpenWhatsAppActivation()
    {
        if (_license == null) return;
        Process.Start(new ProcessStartInfo(_license.WhatsAppActivationUrl) { UseShellExecute = true });
    }

    /// BUG FIX (paritate cu Mac, 2026-08-26): fara fereastra dedicata de
    /// input, un client care primea codul pe WhatsApp nu avea cum sa-l
    /// introduca in aplicatie.
    private void PromptActivationCode()
    {
        if (_license == null) return;
        var window = new ActivationInputWindow();
        if (window.ShowDialog() != true || string.IsNullOrWhiteSpace(window.EnteredCode)) return;

        var error = _license.Activate(window.EnteredCode);
        if (error == null)
        {
            RefreshLicenseMenuText();
            System.Windows.MessageBox.Show(
                "Licenta a fost activata cu succes. Multumim pentru sustinere!",
                "Activare reusita", MessageBoxButton.OK, MessageBoxImage.Information);
        }
        else
        {
            System.Windows.MessageBox.Show(ActivationErrorText(error.Value),
                "Activare esuata", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }

    private static string ActivationErrorText(LicenseCore.ValidationError error) => error switch
    {
        LicenseCore.ValidationError.MalformedCode => "Codul introdus nu e valid (format gresit).",
        LicenseCore.ValidationError.BadSignature => "Codul nu a putut fi verificat (semnatura invalida).",
        LicenseCore.ValidationError.WrongProduct => "Acest cod e pentru alta aplicatie.",
        LicenseCore.ValidationError.WrongMachine => "Acest cod e blocat pe alt calculator. Trimite Machine ID-ul curent pentru un cod nou.",
        LicenseCore.ValidationError.Expired => "Codul a expirat.",
        _ => "Eroare necunoscuta.",
    };

    private static void LogCrash(string source, Exception? ex)
    {
        try
        {
            File.AppendAllText(CrashLogPath,
                $"[{DateTime.Now:O}] {source}\n{ex?.GetType().FullName}: {ex?.Message}\n{ex?.StackTrace}\n\n");
        }
        catch
        {
            // nimic altceva de facut daca nu putem scrie log-ul
        }
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _trayIcon?.Dispose();
        _hotkey?.Dispose();
        _metrics?.Stop();
        _logWatcher?.Stop();
        base.OnExit(e);
    }
}
