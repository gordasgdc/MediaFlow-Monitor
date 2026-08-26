using System;
using System.IO;
using Microsoft.UI.Xaml;
using MediaFlowMonitor.LogEngine;
using MediaFlowMonitor.SystemMetrics;
using MediaFlowMonitor.Overlay;

namespace MediaFlowMonitor;

/// Entry point — fără fereastră principală vizibilă, doar overlay + tray icon.
public partial class App : Application
{
    private DaVinciLogWatcher? _logWatcher;
    private SystemMetricsMonitor? _metrics;
    private OverlayWindow? _overlay;
    private GlobalHotkey? _hotkey;

    private static readonly string CrashLogPath = Path.Combine(Path.GetTempPath(), "MediaFlowMonitor-crash.log");

    public App()
    {
        // DIAGNOSTIC (2026-08-26): aplicatia crapa la lansare pe ARM64
        // Windows (Parallels), fara nicio urma .NET vizibila — doar
        // Exception code: 0xc0000409 in Event Viewer, modul "unknown".
        // Handler-ele de mai jos scriu orice exceptie .NET intr-un fisier
        // INAINTE ca procesul sa se inchida, ca sa vedem cauza reala.
        AppDomain.CurrentDomain.UnhandledException += (_, e) =>
            LogCrash("AppDomain.UnhandledException", e.ExceptionObject as Exception);
        this.UnhandledException += (_, e) =>
        {
            LogCrash("Application.UnhandledException", e.Exception);
            e.Handled = true; // nu lasa aplicatia sa crape daca putem continua
        };
        System.Threading.Tasks.TaskScheduler.UnobservedTaskException += (_, e) =>
            LogCrash("TaskScheduler.UnobservedTaskException", e.Exception);

        try
        {
            InitializeComponent();
        }
        catch (Exception ex)
        {
            LogCrash("InitializeComponent", ex);
            throw;
        }
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

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        LogCrash("OnLaunched: start", null);
        try
        {
            _metrics = new SystemMetricsMonitor();
            _metrics.Start();
            LogCrash("OnLaunched: metrics started OK", null);

            _logWatcher = new DaVinciLogWatcher();
            _logWatcher.Start();
            LogCrash("OnLaunched: logWatcher started OK", null);

            _overlay = new OverlayWindow(_metrics, _logWatcher);
            LogCrash("OnLaunched: overlay created OK", null);

            // Ctrl+Shift+M — toggle overlay (nativ, via RegisterHotKey)
            _hotkey = new GlobalHotkey(modifiers: HotkeyModifiers.Control | HotkeyModifiers.Shift, key: 0x4D /* 'M' */);
            _hotkey.Pressed += (_, _) => _overlay.Toggle();
            LogCrash("OnLaunched: hotkey registered OK - all done", null);
        }
        catch (Exception ex)
        {
            LogCrash("OnLaunched: EXCEPTION", ex);
            throw;
        }
    }
}
