using System.Windows;

namespace MediaFlowMonitor;

/// Fereastra minimala de progres, afisata cat timp `SelfUpdater` descarca
/// installer-ul. Vezi SelfUpdater.cs pentru fluxul complet.
public partial class UpdateProgressWindow : Window
{
    public UpdateProgressWindow(string version)
    {
        InitializeComponent();
        TitleText.Text = $"MediaFlow Monitor {version}";
    }

    public void SetStatus(string text) => StatusText.Text = text;
}
