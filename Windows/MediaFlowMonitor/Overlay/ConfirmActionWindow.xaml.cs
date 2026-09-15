using System.Windows;

namespace MediaFlowMonitor.Overlay;

/// Dialog de confirmare cu bifa optionala „nu ma mai intreba" — MessageBox-ul
/// WPF nu are asa ceva, iar pe Mac dialogul echivalent o are (paritate).
public partial class ConfirmActionWindow : Window
{
    /// True daca utilizatorul a bifat „nu ma mai intreba". Citit doar cand
    /// dialogul s-a inchis cu confirmare.
    public bool SuppressFuture => SuppressCheck.IsChecked == true;

    public ConfirmActionWindow(string title, string body, string confirmLabel, string? suppressLabel = null)
    {
        InitializeComponent();
        TitleText.Text = title;
        BodyText.Text = body;
        ConfirmButton.Content = confirmLabel;
        if (suppressLabel is not null)
        {
            SuppressCheck.Content = suppressLabel;
            SuppressCheck.Visibility = Visibility.Visible;
        }
    }

    private void OnConfirm(object sender, RoutedEventArgs e) => DialogResult = true;
    private void OnCancel(object sender, RoutedEventArgs e) => DialogResult = false;
}
