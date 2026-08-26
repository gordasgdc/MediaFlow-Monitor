using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using MediaFlowMonitor.LogEngine;
using MediaFlowMonitor.SystemMetrics;

namespace MediaFlowMonitor.Overlay;

/// Fereastra mica, fara chrome, toggle pe hotkey. Skeleton — binding
/// complet la un ViewModel poate urma intr-o etapa viitoare; pentru acum
/// actualizeaza direct controalele, la fel de simplu si suficient pentru
/// o fereastra atat de mica.
public partial class OverlayWindow : Window
{
    private readonly SystemMetricsMonitor _metrics;
    private readonly DaVinciLogWatcher _logWatcher;
    private bool _isVisible;

    public OverlayWindow(SystemMetricsMonitor metrics, DaVinciLogWatcher logWatcher)
    {
        InitializeComponent();
        _metrics = metrics;
        _logWatcher = logWatcher;

        _metrics.SnapshotReady += (_, snapshot) => Dispatcher.Invoke(() => UpdateMetrics(snapshot));
        _logWatcher.SignalDetected += (_, signal) => Dispatcher.Invoke(() => UpdateSignal(signal));

        // Pozitioneaza in coltul din dreapta-sus, ca overlay-ul de pe macOS.
        var workArea = SystemParameters.WorkArea;
        Loaded += (_, _) =>
        {
            Left = workArea.Right - Width - 20;
            Top = workArea.Top + 20;
        };
    }

    public void Toggle()
    {
        if (_isVisible)
        {
            Hide();
        }
        else
        {
            Show();
            Activate();
        }
        _isVisible = !_isVisible;
    }

    private void UpdateMetrics(MemorySnapshot snapshot)
    {
        var ramPct = snapshot.RamTotalGB > 0 ? snapshot.RamUsedGB / snapshot.RamTotalGB * 100 : 0;
        RamBar.Value = ramPct;
        RamPercentText.Text = $"{(int)ramPct}%";

        var swapPct = Math.Min(snapshot.SwapUsedGB / 8.0 * 100, 100);
        SwapBar.Value = swapPct;
        SwapPercentText.Text = $"{(int)swapPct}%";

        StatusDot.Fill = snapshot.SwapLevel switch
        {
            MetricLevel.Critical => (Brush)FindResource("Crit"),
            MetricLevel.Warning => (Brush)FindResource("Warn"),
            _ => (Brush)FindResource("Ok"),
        };
    }

    private void UpdateSignal(ResolveLogSignal signal)
    {
        var (text, level) = signal.Kind switch
        {
            ResolveLogSignalKind.PluginCrash => ($"Plugin crapat: {signal.Detail}", MetricLevel.Critical),
            ResolveLogSignalKind.GpuMemoryFull => ("GPU Memory Full", MetricLevel.Critical),
            ResolveLogSignalKind.DroppedFrames => ($"{signal.Value} cadre pierdute", MetricLevel.Warning),
            ResolveLogSignalKind.RenderCacheRegenerated => ("Render Cache regenerat", MetricLevel.Warning),
            ResolveLogSignalKind.FusionSlowNode => ($"Nod Fusion lent ({signal.Value}ms)", MetricLevel.Warning),
            ResolveLogSignalKind.CodecSoftwareFallback => ("Decodare software (fallback)", MetricLevel.Warning),
            ResolveLogSignalKind.DbConnectionLost => ("Conexiune baza de date pierduta", MetricLevel.Critical),
            _ => ("Semnal necunoscut", MetricLevel.Warning),
        };

        var brush = level == MetricLevel.Critical ? (Brush)FindResource("Crit") : (Brush)FindResource("Warn");
        var tb = new TextBlock { Text = "• " + text, Foreground = brush, FontSize = 11, Margin = new Thickness(0, 2, 0, 0) };
        AlertsPanel.Children.Insert(0, tb);
        while (AlertsPanel.Children.Count > 5)
        {
            AlertsPanel.Children.RemoveAt(AlertsPanel.Children.Count - 1);
        }

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
    }

    private void OnActionClicked(object sender, RoutedEventArgs e)
    {
        // TODO: integrare reala — placeholder, la fel ca pe macOS.
        ActionButton.Visibility = Visibility.Collapsed;
    }
}
