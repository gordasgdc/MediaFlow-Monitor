using System;
using System.ComponentModel;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shapes;
using MediaFlowMonitor.LogEngine;
using MediaFlowMonitor.SystemMetrics;

namespace MediaFlowMonitor.Overlay;

/// Dashboard Pro pe Windows — paritate cu DashboardView.swift: grafice live
/// VRAM/Swap + CPU per-core (desenate procedural, mai sigur decât binding-uri
/// XAML complexe pentru un chart), Log Decoder colorat, recomandări,
/// panou CacheClip (auto + manual, discuri externe incluse), consolă live
/// de execuție pentru Purge Cache/Force Sync Log/Optimise System, toast,
/// selector explicit de temă System/Dark/Light.
public partial class OverlayWindow : Window
{
    private readonly DashboardViewModel _vm;
    private bool _isVisible;
    private ActionConsoleWindow? _consoleWindow;

    public OverlayWindow(SystemMetricsMonitor metrics, DaVinciLogWatcher logWatcher)
    {
        InitializeComponent();

        _vm = new DashboardViewModel(metrics, logWatcher);
        DataContext = _vm;
        _vm.PropertyChanged += OnViewModelPropertyChanged;
        _vm.VramHistory.CollectionChanged += (_, _) => RedrawPerformanceChart();
        _vm.SwapHistory.CollectionChanged += (_, _) => RedrawPerformanceChart();

        ThemeSystemRadio.IsChecked = ThemeManager.Shared.Current == AppTheme.System;
        ThemeLightRadio.IsChecked = ThemeManager.Shared.Current == AppTheme.Light;
        ThemeDarkRadio.IsChecked = ThemeManager.Shared.Current == AppTheme.Dark;

        Loaded += (_, _) =>
        {
            var workArea = SystemParameters.WorkArea;
            Left = Math.Max(workArea.Left, workArea.Right - Width - 20);
            Top = workArea.Top + 20;
            RedrawPerformanceChart();
            RedrawCpuBars();
            UpdateHealthDetailTexts();
            UpdateCacheDiskPanel();
        };
    }

    public void Toggle()
    {
        if (_isVisible) Hide();
        else { Show(); Activate(); }
        _isVisible = !_isVisible;
    }

    private void OnViewModelPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        switch (e.PropertyName)
        {
            case nameof(DashboardViewModel.VramUsedGB):
            case nameof(DashboardViewModel.DiskInfo):
                UpdateHealthDetailTexts();
                UpdateCacheDiskPanel();
                RedrawPerformanceChart();
                break;
            case nameof(DashboardViewModel.CpuPerCore):
                RedrawCpuBars();
                break;
            case nameof(DashboardViewModel.LastActionMessage):
                LastActionMessageText.Text = _vm.RunningAction == RunningAction.None ? _vm.LastActionMessage : "";
                break;
            case nameof(DashboardViewModel.ActionToast):
                UpdateToast();
                break;
            case nameof(DashboardViewModel.ShowActionConsole):
                if (_vm.ShowActionConsole) ShowConsoleWindow();
                break;
        }
    }

    // MARK: - Grafic VRAM/Swap (Canvas desenat procedural)

    private void OnPerformanceCanvasSizeChanged(object sender, SizeChangedEventArgs e) => RedrawPerformanceChart();

    private void RedrawPerformanceChart()
    {
        PerformanceCanvas.Children.Clear();
        double w = PerformanceCanvas.ActualWidth, h = PerformanceCanvas.ActualHeight;
        if (w <= 0 || h <= 0) return;

        DrawSeries(_vm.VramHistory, System.Windows.Media.Brushes.DodgerBlue, w, h);
        DrawSeries(_vm.SwapHistory, System.Windows.Media.Brushes.IndianRed, w, h);
    }

    private void DrawSeries(System.Collections.Generic.IReadOnlyList<HistoryPoint> points, System.Windows.Media.Brush brush, double w, double h)
    {
        if (points.Count < 2) return;
        double max = Math.Max(points.Max(p => p.Value), 1);
        var poly = new Polyline { Stroke = brush, StrokeThickness = 1.5 };
        for (int i = 0; i < points.Count; i++)
        {
            double x = w * i / (points.Count - 1);
            double y = h - (points[i].Value / max * h);
            poly.Points.Add(new System.Windows.Point(x, y));
        }
        PerformanceCanvas.Children.Add(poly);
    }

    // MARK: - Bare CPU per-core

    private void RedrawCpuBars()
    {
        CpuBarsControl.Items.Clear();
        var cores = _vm.CpuPerCore;
        CpuHeaderText.Text = $"CPU Thread 1–{Math.Max(cores.Length, 1)}";
        for (int i = 0; i < cores.Length; i++)
        {
            double usage = cores[i];
            var brush = usage > 0.85 ? System.Windows.Media.Brushes.IndianRed : usage > 0.6 ? System.Windows.Media.Brushes.Goldenrod : System.Windows.Media.Brushes.MediumSeaGreen;
            var bar = new System.Windows.Shapes.Rectangle
            {
                Width = 20,
                Height = Math.Max(2, usage * 120),
                Fill = brush,
                Margin = new Thickness(2, 0, 2, 0),
                VerticalAlignment = VerticalAlignment.Bottom,
            };
            CpuBarsControl.Items.Add(bar);
        }
    }

    // MARK: - Health detail + CacheClip panel (text simplu, mai sigur decât binding complex)

    private void UpdateHealthDetailTexts()
    {
        VramText.Text = _vm.VramUsedGB is { } v ? $"{v:F1} GB" : "—";
        var disk = _vm.DiskInfo;
        PartitionText.Text = disk != null ? $"{disk.TotalGB:F0} GB" : "—";
        CacheClipFreeText.Text = disk != null ? $"{disk.FreeGB:F0} GB liber" : "—";
    }

    private void UpdateCacheDiskPanel()
    {
        var disk = _vm.DiskInfo;
        if (disk == null)
        {
            CacheDiskUsageBar.Value = 0;
            CacheDiskUsageText.Text = "Folderul CacheClip nu a fost găsit încă.";
            CacheDiskHealthText.Text = "";
            CacheDiskPathText.Text = "";
            return;
        }
        CacheDiskUsageBar.Value = disk.TotalGB > 0 ? disk.UsedGB / disk.TotalGB : 0;
        CacheDiskUsageText.Text = $"Disk Usage: {disk.UsedGB:F1} GB / {disk.TotalGB:F0} GB";
        CacheDiskHealthText.Text = disk.IsHealthy switch { true => "Healthy", false => "Failing", _ => "Necunoscut" };
        CacheDiskPathText.Text = (_vm.CachePathIsManual ? "Cale (manuală): " : "Cale (auto-detectată): ") + disk.Path;
    }

    private void UpdateToast()
    {
        if (_vm.ActionToast is { } toast)
        {
            ToastText.Text = (toast.Success ? "✓ " : "✕ ") + toast.Text;
            ToastBorder.Visibility = Visibility.Visible;
        }
        else
        {
            ToastBorder.Visibility = Visibility.Collapsed;
        }
    }

    // MARK: - Consolă live de execuție

    private void ShowConsoleWindow()
    {
        if (_consoleWindow == null)
        {
            _consoleWindow = new ActionConsoleWindow(_vm) { Owner = this };
            _consoleWindow.Closed += (_, _) => _consoleWindow = null;
        }
        _consoleWindow.Show();
        _consoleWindow.Activate();
    }

    // MARK: - Handlere UI

    private void OnThemeRadioChecked(object sender, RoutedEventArgs e)
    {
        if (sender is RadioButton { Tag: string tag } && Enum.TryParse<AppTheme>(tag, out var theme))
            ThemeManager.Shared.Set(theme);
    }

    private void OnChooseFolderClicked(object sender, RoutedEventArgs e) => _vm.ChooseCacheFolderManually();

    private void OnForceSyncClicked(object sender, RoutedEventArgs e) => _vm.ForceSyncLog();

    private void OnOptimiseClicked(object sender, RoutedEventArgs e) => _vm.OptimiseSystem();

    private void OnShowConsoleClicked(object sender, RoutedEventArgs e) => ShowConsoleWindow();

    private void OnPurgeCacheClicked(object sender, RoutedEventArgs e)
    {
        var path = CacheFolderLocator.ActivePath;
        var result = System.Windows.MessageBox.Show(
            $"Golește tot conținutul din {path}?",
            "Confirmare Purge Cache", MessageBoxButton.YesNo, MessageBoxImage.Warning);
        if (result != MessageBoxResult.Yes) return;
        _vm.RequestPurgeCache(callback => callback(true));
    }

    private void OnCloseClicked(object sender, RoutedEventArgs e) => Hide();
}
