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

    public App()
    {
        InitializeComponent();
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        _metrics = new SystemMetricsMonitor();
        _metrics.Start();

        _logWatcher = new DaVinciLogWatcher();
        _logWatcher.Start();

        _overlay = new OverlayWindow(_metrics, _logWatcher);

        // Ctrl+Shift+M — toggle overlay (nativ, via RegisterHotKey)
        _hotkey = new GlobalHotkey(modifiers: HotkeyModifiers.Control | HotkeyModifiers.Shift, key: 0x4D /* 'M' */);
        _hotkey.Pressed += (_, _) => _overlay.Toggle();
    }
}
