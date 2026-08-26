using System;
using System.IO;
using System.Windows;
using System.Windows.Forms;
using MediaFlowMonitor.LogEngine;
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
        menu.Items.Add("Iesire", null, (_, _) => Shutdown());

        _trayIcon = new NotifyIcon
        {
            Icon = System.Drawing.SystemIcons.Application,
            Visible = true,
            Text = "MediaFlow Monitor",
            ContextMenuStrip = menu,
        };
        _trayIcon.DoubleClick += (_, _) => _overlay?.Toggle();
    }

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
