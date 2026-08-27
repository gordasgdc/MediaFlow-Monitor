using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Windows;

namespace MediaFlowMonitor;

/// Descarcă și lansează automat installer-ul de update, fără să mai treacă
/// prin browser/pagina de GitHub — oglinda SelfUpdater.swift (Mac) și
/// SelfUpdater.cs (GDCVaultWin/GDCPluginManagerWin). Vezi CLAUDE.md Partea
/// 1, Regula 20 — prima implementare de update checker/self-update pe
/// Windows pentru acest proiect (lipsea complet).
///
/// WARNING: pasul de instalare efectiv (wizard-ul Inno, click-urile
/// userului) NU poate fi verificat automat de Claude.
public static class SelfUpdater
{
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromMinutes(5) };

    public static async Task DownloadAndInstallAsync(string downloadUrl, string version)
    {
        var progress = new UpdateProgressWindow(version);
        progress.Show();

        try
        {
            var tempDir = Path.Combine(Path.GetTempPath(), "mediaflowmonitor-update-" + Guid.NewGuid());
            Directory.CreateDirectory(tempDir);

            progress.SetStatus("Se descarcă actualizarea…");
            var exePath = Path.Combine(tempDir, $"MediaFlowMonitorSetup-{version}.exe");
            await DownloadAsync(downloadUrl, exePath);

            progress.SetStatus("Se lansează instalatorul…");
            Process.Start(new ProcessStartInfo(exePath) { UseShellExecute = true });

            progress.Close();
            Application.Current.Shutdown();
        }
        catch (Exception ex)
        {
            progress.Close();
            PresentFailure(ex.Message);
        }
    }

    private static async Task DownloadAsync(string url, string destination)
    {
        using var response = await Http.GetAsync(url, HttpCompletionOption.ResponseHeadersRead);
        if (!response.IsSuccessStatusCode)
        {
            throw new InvalidOperationException($"Descărcarea a eșuat: HTTP {(int)response.StatusCode}");
        }
        await using var httpStream = await response.Content.ReadAsStreamAsync();
        await using var fileStream = File.Create(destination);
        await httpStream.CopyToAsync(fileStream);
    }

    private static void PresentFailure(string message)
    {
        MessageBox.Show(
            $"{message}\n\nPoți descărca manual ultima versiune de pe pagina de GitHub.",
            "Actualizarea a eșuat", MessageBoxButton.OK, MessageBoxImage.Warning);
    }
}
