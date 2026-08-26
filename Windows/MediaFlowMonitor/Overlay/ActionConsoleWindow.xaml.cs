using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;

namespace MediaFlowMonitor.Overlay;

/// Consolă live stil Terminal pentru Purge Cache / Force Sync Log /
/// Optimise System — echivalentul sheet-ului SwiftUI de pe Mac.
public partial class ActionConsoleWindow : Window
{
    private readonly DashboardViewModel _vm;

    public ActionConsoleWindow(DashboardViewModel vm)
    {
        InitializeComponent();
        _vm = vm;
        DataContext = vm;
        _vm.PropertyChanged += OnVmPropertyChanged;
        _vm.ActionLog.CollectionChanged += (_, _) => ScrollToEnd();
        UpdateStatus();
    }

    private void OnVmPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(DashboardViewModel.RunningAction)) UpdateStatus();
    }

    private void UpdateStatus()
    {
        bool running = _vm.RunningAction != RunningAction.None;
        StatusText.Text = running ? "Se execută…" : "Proces finalizat";
        CloseButton.IsEnabled = !running;
    }

    private void ScrollToEnd() => LogScroll.ScrollToEnd();

    private void OnCloseClicked(object sender, RoutedEventArgs e) => Close();
}
