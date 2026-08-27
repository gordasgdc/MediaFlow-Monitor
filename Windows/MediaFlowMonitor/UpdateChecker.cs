using System.IO;
using System.Linq;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace MediaFlowMonitor;

/// Oglinda UpdateChecker.swift (Mac) — citește ACELAȘI `update.json`
/// (gordas.dev/media-flow-monitor/update.json), nu un endpoint separat.
/// Prima implementare de update checker pe Windows pentru acest proiect
/// (lipsea complet — vezi CLAUDE.md Partea 1, Regula 20, status per-repo).
public sealed class UpdateInfo
{
    [JsonPropertyName("version")]
    public string Version { get; set; } = "";

    [JsonPropertyName("changes")]
    public string? Changes { get; set; }

    [JsonPropertyName("download_url")]
    public Dictionary<string, string> DownloadUrl { get; set; } = new();

    [JsonPropertyName("mandatory")]
    public bool Mandatory { get; set; }
}

public static class UpdateChecker
{
    private static readonly Uri UpdateJsonUrl = new("https://gordas.dev/media-flow-monitor/update.json");
    private const string DismissedVersionKey = "MediaFlowMonitor.dismissedUpdateVersion";

    private static readonly HttpClient Http = new();

    static UpdateChecker()
    {
        Http.DefaultRequestHeaders.UserAgent.Add(new ProductInfoHeaderValue("MediaFlowMonitor", CurrentVersion));
        Http.DefaultRequestHeaders.CacheControl = new System.Net.Http.Headers.CacheControlHeaderValue { NoCache = true };
        Http.Timeout = TimeSpan.FromSeconds(10);
    }

    public static string CurrentVersion =>
        System.Reflection.Assembly.GetEntryAssembly()?.GetName().Version?.ToString(3) ?? "0";

    /// Dublu cache-bypass (query param unic + header no-cache), la fel ca
    /// pe Mac — CDN-urile din fața gordas.dev pot cache-ui pe URL complet.
    public static async Task<UpdateInfo?> FetchAsync()
    {
        var urlWithBuster = $"{UpdateJsonUrl}?t={DateTimeOffset.UtcNow.ToUnixTimeSeconds()}";
        using var response = await Http.GetAsync(urlWithBuster);
        if (!response.IsSuccessStatusCode) return null;
        var data = await response.Content.ReadAsByteArrayAsync();
        return JsonSerializer.Deserialize<UpdateInfo>(data);
    }

    public static bool IsNewer(string remote, string current) => SemVerCompare(remote, current) > 0;

    /// Comparare SemVer robustă, port 1:1 al `semVerCompare` (Mac).
    public static int SemVerCompare(string a, string b)
    {
        static int[] Parts(string s)
        {
            if (s.StartsWith("v", StringComparison.OrdinalIgnoreCase)) s = s[1..];
            return s.Split('.').Select(p =>
            {
                var digits = new string(p.TakeWhile(char.IsDigit).ToArray());
                return int.TryParse(digits, out var n) ? n : 0;
            }).ToArray();
        }
        var pa = Parts(a);
        var pb = Parts(b);
        for (var i = 0; i < Math.Max(pa.Length, pb.Length); i++)
        {
            var va = i < pa.Length ? pa[i] : 0;
            var vb = i < pb.Length ? pb[i] : 0;
            if (va != vb) return va > vb ? 1 : -1;
        }
        return 0;
    }

    public static bool WasDismissed(string version) => ReadDismissedVersion() == version;

    public static void MarkDismissed(string version)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(DismissedVersionFilePath)!);
            File.WriteAllText(DismissedVersionFilePath, version);
        }
        catch { /* nescriere nu trebuie sa blocheze UI-ul */ }
    }

    private static string DismissedVersionFilePath =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "MediaFlowMonitor", "dismissed-update-version.txt");

    private static string? ReadDismissedVersion()
    {
        try { return File.Exists(DismissedVersionFilePath) ? File.ReadAllText(DismissedVersionFilePath).Trim() : null; }
        catch { return null; }
    }
}
