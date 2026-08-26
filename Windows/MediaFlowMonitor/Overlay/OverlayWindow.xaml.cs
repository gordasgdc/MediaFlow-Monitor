using Microsoft.UI.Xaml;
using MediaFlowMonitor.LogEngine;
using MediaFlowMonitor.SystemMetrics;

namespace MediaFlowMonitor.Overlay;

/// Fereastră mică, borderless-style (via WinUI acrylic), toggle pe hotkey.
/// Skeleton — binding complet la ViewModel urmează în etapa următoare.
public sealed partial class OverlayWindow : Window
{
    private readonly SystemMetricsMonitor _metrics;
    private readonly DaVinciLogWatcher _logWatcher;
    private bool _isVisible;

    public OverlayWindow(SystemMetricsMonitor metrics, DaVinciLogWatcher logWatcher)
    {
        InitializeComponent();
        _metrics = metrics;
        _logWatcher = logWatcher;

        TitleText.Text = "MediaFlow";
        _metrics.SnapshotReady += (_, snapshot) => UpdateMetrics(snapshot);
        _logWatcher.SignalDetected += (_, signal) => UpdateSignal(signal);

        AppWindow.Hide(); // pornește ascuns, exact ca overlay-ul macOS
    }

    public void Toggle()
    {
        if (_isVisible) AppWindow.Hide();
        else AppWindow.Show();
        _isVisible = !_isVisible;
    }

    private void UpdateMetrics(MemorySnapshot snapshot)
    {
        DispatcherQueue.TryEnqueue(() =>
        {
            RamRing.Value = snapshot.RamUsedGB / snapshot.RamTotalGB * 100;
            RamPercentText.Text = $"{(int)RamRing.Value}%";
            SwapRing.Value = System.Math.Min(snapshot.SwapUsedGB / 8.0 * 100, 100);
            SwapPercentText.Text = $"{(int)SwapRing.Value}%";
        });
    }

    private void UpdateSignal(ResolveLogSignal signal)
    {
        DispatcherQueue.TryEnqueue(() =>
        {
            if (signal.Kind is ResolveLogSignalKind.GpuMemoryFull or ResolveLogSignalKind.FusionSlowNode)
            {
                ActionButton.Content = "Bypass FX";
                ActionButton.Visibility = Visibility.Visible;
            }
            else if (signal.Kind == ResolveLogSignalKind.RenderCacheRegenerated)
            {
                ActionButton.Content = "Purge Cache";
                ActionButton.Visibility = Visibility.Visible;
            }
        });
    }

    private void OnActionClicked(object sender, RoutedEventArgs e)
    {
        // TODO: integrare reală — placeholder, la fel ca pe macOS.
        ActionButton.Visibility = Visibility.Collapsed;
    }
}
