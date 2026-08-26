using System.Windows;

namespace MediaFlowMonitor.Licensing;

/// Fereastră simplă de input pentru codul de activare — echivalentul
/// NSAlert+NSTextField de pe Mac. WPF nu are un input-box nativ.
public partial class ActivationInputWindow : Window
{
    public string? EnteredCode { get; private set; }

    public ActivationInputWindow()
    {
        InitializeComponent();
        Loaded += (_, _) => CodeTextBox.Focus();
    }

    private void OnActivateClicked(object sender, RoutedEventArgs e)
    {
        EnteredCode = CodeTextBox.Text.Trim();
        DialogResult = true;
    }

    private void OnCancelClicked(object sender, RoutedEventArgs e)
    {
        DialogResult = false;
    }
}
