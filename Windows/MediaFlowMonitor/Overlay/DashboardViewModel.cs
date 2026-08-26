using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Threading.Tasks;
using System.Windows.Threading;
using MediaFlowMonitor.LogEngine;
using MediaFlowMonitor.SystemMetrics;

namespace MediaFlowMonitor.Overlay;

public enum ActionLogLevel { Info, Exec, Success, Error }
public enum RunningAction { None, PurgeCache, ForceSyncLog, OptimiseSystem, ForceKillDaVinci }
public enum LogFilter { All, Errors, Warnings, RenderEvents }

public sealed record LogConsoleEntry(DateTime Date, string Text, MetricLevel Level, bool IsRenderEvent = false);
public sealed record ActionLogEntry(DateTime Date, string Text, ActionLogLevel Level);
public sealed record Recommendation(string Text, MetricLevel Level);

/// Echivalentul DashboardViewModel.swift — orchestrează metrice, istoric de
/// grafice, consola de log decodat, recomandările și acțiunile (cu consolă
/// live stil Terminal, identic cu Dashboard-ul de pe Mac).
public sealed class DashboardViewModel : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;
    private void Raise([CallerMemberName] string? name = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));

    private readonly SystemMetricsMonitor _metrics;
    private readonly DaVinciLogWatcher? _logWatcher;
    private readonly Dispatcher _dispatcher;
    private const int MaxConsoleLines = 60;

    private readonly MetricsHistory _vramHistoryStore = new();
    private readonly MetricsHistory _swapHistoryStore = new();
    private readonly MetricsHistory _cpuHistoryStore = new();

    public double RamFraction { get => _ramFraction; private set { _ramFraction = value; Raise(); } }
    private double _ramFraction;
    public double SwapFraction { get => _swapFraction; private set { _swapFraction = value; Raise(); } }
    private double _swapFraction;
    public MetricLevel RamLevel { get => _ramLevel; private set { _ramLevel = value; Raise(); } }
    private MetricLevel _ramLevel;
    public MetricLevel SwapLevel { get => _swapLevel; private set { _swapLevel = value; Raise(); } }
    private MetricLevel _swapLevel;
    public MetricLevel OverallLevel { get => _overallLevel; private set { _overallLevel = value; Raise(); } }
    private MetricLevel _overallLevel;
    public double? VramUsedGB { get => _vramUsedGB; private set { _vramUsedGB = value; Raise(); } }
    private double? _vramUsedGB;
    public double[] CpuPerCore { get => _cpuPerCore; private set { _cpuPerCore = value; Raise(); } }
    private double[] _cpuPerCore = Array.Empty<double>();

    public DiskInfo? DiskInfo { get => _diskInfo; private set { _diskInfo = value; Raise(); } }
    private DiskInfo? _diskInfo;
    public bool CachePathIsManual { get => _cachePathIsManual; private set { _cachePathIsManual = value; Raise(); } }
    private bool _cachePathIsManual;

    public ObservableCollection<HistoryPoint> VramHistory { get; } = new();
    public ObservableCollection<HistoryPoint> SwapHistory { get; } = new();

    public ObservableCollection<ProcessUsage> TopRamProcesses { get; } = new();
    public ObservableCollection<ProcessUsage> TopSwapProcesses { get; } = new();

    private readonly List<LogConsoleEntry> _allLogEntries = new();
    private readonly List<LogConsoleEntry> _pausedLogBuffer = new();
    public ObservableCollection<LogConsoleEntry> LogConsole { get; } = new();
    public ObservableCollection<Recommendation> Recommendations { get; } = new();
    public ObservableCollection<ActionLogEntry> ActionLog { get; } = new();

    public LogFilter LogFilter { get => _logFilter; set { _logFilter = value; Raise(); RebuildFilteredLog(); } }
    private LogFilter _logFilter = LogFilter.All;
    public bool IsLogPaused { get => _isLogPaused; private set { _isLogPaused = value; Raise(); } }
    private bool _isLogPaused;
    public int ErrorCount => _allLogEntries.Count(e => e.Level == MetricLevel.Critical);
    public int WarningCount => _allLogEntries.Count(e => e.Level == MetricLevel.Warning);

    public bool HangingDaVinciDetected { get => _hangingDaVinciDetected; private set { _hangingDaVinciDetected = value; Raise(); } }
    private bool _hangingDaVinciDetected;

    /// Alertă nativă (System Banner) — OverlayWindow abonează un balloon tip
    /// pe NotifyIcon la acest eveniment, identic ca UX cu UNUserNotification pe Mac.
    public event EventHandler<(string Title, string Body)>? BannerRequested;
    private bool _swapBannerSent;
    private bool _diskBannerSent;

    public RunningAction RunningAction { get => _runningAction; private set { _runningAction = value; Raise(); } }
    private RunningAction _runningAction = RunningAction.None;
    public bool ShowActionConsole { get => _showActionConsole; set { _showActionConsole = value; Raise(); } }
    private bool _showActionConsole;
    public string? LastActionMessage { get => _lastActionMessage; private set { _lastActionMessage = value; Raise(); } }
    private string? _lastActionMessage;
    public (string Text, bool Success)? ActionToast { get => _actionToast; private set { _actionToast = value; Raise(); } }
    private (string Text, bool Success)? _actionToast;

    private readonly DispatcherTimer _diskCheckTimer;

    public DashboardViewModel(SystemMetricsMonitor metrics, DaVinciLogWatcher? logWatcher)
    {
        _metrics = metrics;
        _logWatcher = logWatcher;
        _dispatcher = Dispatcher.CurrentDispatcher;

        _metrics.SnapshotReady += (_, snapshot) => _dispatcher.Invoke(() => Apply(snapshot));
        if (_logWatcher != null)
            _logWatcher.SignalDetected += (_, signal) => _dispatcher.Invoke(() => Apply(signal));

        CachePathIsManual = CacheFolderLocator.IsManualOverride;
        CheckDisk();
        CheckHangingDaVinci();
        _diskCheckTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(60) };
        _diskCheckTimer.Tick += (_, _) => { CheckDisk(); CheckHangingDaVinci(); };
        _diskCheckTimer.Start();
    }

    private void CheckDisk()
    {
        DiskInfo = CacheFolderLocator.GetDiskInfo();
        if (DiskInfo is { } disk)
        {
            if (disk.FreeGB < 10)
                SendBanner("disk-low", "CacheClip disk aproape plin", $"Doar {disk.FreeGB:F1} GB liberi — golește cache-ul cât mai curând.", ref _diskBannerSent);
            else
                _diskBannerSent = false;
        }
        UpdateRecommendations();
    }

    /// Vezi checkHangingDaVinci() de pe Mac: proces "Resolve" activ, dar
    /// fără nicio fereastră vizibilă — semn că a rămas agățat în fundal.
    private void CheckHangingDaVinci()
    {
        HangingDaVinciDetected = ProcessInspector.AnyDaVinciProcessRunning() && !ProcessInspector.IsDaVinciResolveWindowVisible();
        UpdateRecommendations();
    }

    private void SendBanner(string id, string title, string body, ref bool sentFlag)
    {
        if (sentFlag) return;
        sentFlag = true;
        BannerRequested?.Invoke(this, (title, body));
    }

    private void Apply(MemorySnapshot snapshot)
    {
        RamFraction = Math.Min(snapshot.RamUsedGB / Math.Max(snapshot.RamTotalGB, 1), 1);
        SwapFraction = Math.Min(snapshot.SwapUsedGB / 8.0, 1);
        VramUsedGB = snapshot.VramUsedGB;
        CpuPerCore = snapshot.CpuPerCore;
        SyncCollection(TopRamProcesses, snapshot.TopRamProcesses);
        SyncCollection(TopSwapProcesses, snapshot.TopSwapProcesses);
        SwapLevel = snapshot.SwapLevel;
        RamLevel = RamFraction > 0.9 ? MetricLevel.Critical : RamFraction > 0.75 ? MetricLevel.Warning : MetricLevel.Ok;
        OverallLevel = (RamLevel == MetricLevel.Critical || SwapLevel == MetricLevel.Critical) ? MetricLevel.Critical
            : (RamLevel == MetricLevel.Warning || SwapLevel == MetricLevel.Warning) ? MetricLevel.Warning
            : MetricLevel.Ok;

        if (snapshot.VramUsedGB is { } vram)
        {
            _vramHistoryStore.Append(vram * 1024);
            SyncCollection(VramHistory, _vramHistoryStore.Points);
        }
        _swapHistoryStore.Append(snapshot.SwapUsedGB * 1024);
        SyncCollection(SwapHistory, _swapHistoryStore.Points);

        if (SwapFraction > 0.8)
            SendBanner("swap-high", "Swap sistem ridicat", $"Swap la {SwapFraction * 100:F0}% — editorul poate deveni lent.", ref _swapBannerSent);
        else
            _swapBannerSent = false;

        UpdateRecommendations();
    }

    private static void SyncCollection<T>(ObservableCollection<T> target, System.Collections.Generic.IReadOnlyList<T> source)
    {
        target.Clear();
        foreach (var p in source) target.Add(p);
    }

    private void Apply(ResolveLogSignal signal)
    {
        var (text, level, isRenderEvent) = signal.Kind switch
        {
            ResolveLogSignalKind.PluginCrash => ($"Plugin crashed: {signal.Detail}", MetricLevel.Critical, false),
            ResolveLogSignalKind.GpuMemoryFull => ("GPU Memory Full", MetricLevel.Critical, true),
            ResolveLogSignalKind.DroppedFrames => ($"Timeline dropped frame ({signal.Value})", MetricLevel.Warning, true),
            ResolveLogSignalKind.RenderCacheRegenerated => ("Render Cache invalid — regenerated", MetricLevel.Warning, true),
            ResolveLogSignalKind.FusionSlowNode => ($"Fusion composition slow rendering ({signal.Value}ms)", MetricLevel.Warning, true),
            ResolveLogSignalKind.CodecSoftwareFallback => ("Codec fallback to software decode", MetricLevel.Warning, false),
            ResolveLogSignalKind.DbConnectionLost => ("Database connection lost", MetricLevel.Critical, false),
            _ => ("Unknown signal", MetricLevel.Warning, false),
        };

        var entry = new LogConsoleEntry(DateTime.Now, text, level, isRenderEvent);
        if (IsLogPaused)
        {
            _pausedLogBuffer.Insert(0, entry);
        }
        else
        {
            _allLogEntries.Insert(0, entry);
            while (_allLogEntries.Count > MaxConsoleLines) _allLogEntries.RemoveAt(_allLogEntries.Count - 1);
            RebuildFilteredLog();
        }
        Raise(nameof(ErrorCount));
        Raise(nameof(WarningCount));
        UpdateRecommendations();
    }

    /// Pause/Resume Auto-scroll — cât e pe pauză, evenimentele noi se
    /// acumulează separat (nu se pierd), reinjectate la Resume.
    public void ToggleLogPause()
    {
        IsLogPaused = !IsLogPaused;
        if (!IsLogPaused && _pausedLogBuffer.Count > 0)
        {
            _allLogEntries.InsertRange(0, _pausedLogBuffer);
            while (_allLogEntries.Count > MaxConsoleLines) _allLogEntries.RemoveAt(_allLogEntries.Count - 1);
            _pausedLogBuffer.Clear();
            RebuildFilteredLog();
        }
    }

    private void RebuildFilteredLog()
    {
        var filtered = LogFilter switch
        {
            LogFilter.Errors => _allLogEntries.Where(e => e.Level == MetricLevel.Critical),
            LogFilter.Warnings => _allLogEntries.Where(e => e.Level == MetricLevel.Warning),
            LogFilter.RenderEvents => _allLogEntries.Where(e => e.IsRenderEvent),
            _ => _allLogEntries.AsEnumerable(),
        };
        LogConsole.Clear();
        foreach (var e in filtered) LogConsole.Add(e);
    }

    /// Export Log — salvează consola curentă (filtrată după LogFilter)
    /// într-un fișier .txt, un singur click.
    public void ExportLog()
    {
        var dialog = new Microsoft.Win32.SaveFileDialog
        {
            FileName = $"MediaFlowMonitor-Log-{DateTimeOffset.Now.ToUnixTimeSeconds()}.txt",
            Filter = "Fișier text (*.txt)|*.txt",
        };
        if (dialog.ShowDialog() != true) return;
        var lines = LogConsole.Reverse().Select(e =>
        {
            var tag = e.Level == MetricLevel.Critical ? "ERR" : e.Level == MetricLevel.Warning ? "WARN" : "OK";
            return $"{e.Date:HH:mm:ss} [{tag}] {e.Text}";
        });
        System.IO.File.WriteAllLines(dialog.FileName, lines);
    }

    // MARK: - Accesorii & utilitare rapide

    public void OpenCacheFolderInExplorer() => CacheFolderLocator.RevealInExplorer();

    /// Copy Diagnostics — rezumat curat, gata de lipit în WhatsApp/email/forum.
    public void CopyDiagnosticsToClipboard()
    {
        var lines = new List<string>
        {
            "MediaFlow Monitor — Diagnostic",
            $"Windows: {Environment.OSVersion.VersionString}",
            $"RAM: {RamFraction * 100:F1}% (nivel {RamLevel})",
            $"Swap: {SwapFraction * 100:F1}% (nivel {SwapLevel})",
            $"VRAM: {(VramUsedGB is { } v ? $"{v:F1} GB" : "necunoscut")}",
        };
        if (DiskInfo is { } disk)
            lines.Add($"CacheClip disk: {disk.FreeGB:F1} GB liberi din {disk.TotalGB:F0} GB ({disk.Path})");
        var recentErrors = _allLogEntries.Where(e => e.Level == MetricLevel.Critical).Take(5).ToList();
        if (recentErrors.Count > 0)
        {
            lines.Add("Ultimele erori din log:");
            lines.AddRange(recentErrors.Select(e => $"  {e.Date:HH:mm:ss} — {e.Text}"));
        }
        System.Windows.Clipboard.SetText(string.Join(Environment.NewLine, lines));
        ActionToast = ("Diagnostic copiat în clipboard", true);
    }

    /// Force Close Hanging DaVinci — apare doar când e detectat agățat.
    public async void ForceCloseHangingDaVinci()
    {
        if (RunningAction != RunningAction.None) return;
        BeginAction(RunningAction.ForceKillDaVinci);
        ActionLog.Clear();
        LogStep("[INFO] Force Close Hanging DaVinci started…", ActionLogLevel.Info);
        await StepDelay();
        int count = ProcessInspector.ForceKillHangingDaVinci();
        await StepDelay();
        if (count > 0)
        {
            LogStep($"[SUCCESS] Închise {count} proces(e) DaVinci Resolve agățate.", ActionLogLevel.Success);
            HangingDaVinciDetected = false;
            EndAction(true, "DaVinci Resolve închis forțat");
        }
        else
        {
            LogStep("[INFO] Niciun proces agățat găsit.", ActionLogLevel.Info);
            EndAction(true, "Nimic de închis");
        }
        UpdateRecommendations();
    }

    private void UpdateRecommendations()
    {
        Recommendations.Clear();
        if (DiskInfo is { } disk)
        {
            if (disk.FreeGB < 10)
                Recommendations.Add(new Recommendation("Action Required: Purge unused Cache (disk critically low)", MetricLevel.Critical));
            else if (disk.FreeGB < 50)
                Recommendations.Add(new Recommendation("Storage: cache disk approaching full", MetricLevel.Warning));

            if (disk.IsHealthy == false)
                Recommendations.Add(new Recommendation("Disk health: reports FAILING — backup immediately", MetricLevel.Critical));
        }
        if (SwapLevel == MetricLevel.Critical)
            Recommendations.Add(new Recommendation("System Memory: approaching swap limit", MetricLevel.Critical));
        else if (SwapLevel == MetricLevel.Warning)
            Recommendations.Add(new Recommendation("System Memory: swap usage rising", MetricLevel.Warning));

        if (_allLogEntries.Any(e => e.Level == MetricLevel.Critical))
            Recommendations.Add(new Recommendation("Recent critical event in DaVinci log — check console below", MetricLevel.Critical));

        if (HangingDaVinciDetected)
            Recommendations.Add(new Recommendation("DaVinci Resolve pare agățat în fundal (blochează RAM/VRAM) — Force Close Hanging DaVinci", MetricLevel.Critical));

        if (Recommendations.Count == 0)
            Recommendations.Add(new Recommendation("All systems normal", MetricLevel.Ok));
    }

    public void ChooseCacheFolderManually()
    {
        var chosen = CacheFolderLocator.ChooseFolderManually();
        if (chosen == null) return;
        CachePathIsManual = CacheFolderLocator.IsManualOverride;
        CheckDisk();
    }

    // MARK: - Consolă de execuție live

    private void LogStep(string text, ActionLogLevel level = ActionLogLevel.Exec)
    {
        ActionLog.Add(new ActionLogEntry(DateTime.Now, text, level));
        while (ActionLog.Count > 200) ActionLog.RemoveAt(0);
    }

    private void BeginAction(RunningAction action)
    {
        RunningAction = action;
        ShowActionConsole = true;
        ActionToast = null;
    }

    private async void EndAction(bool success, string toast)
    {
        RunningAction = RunningAction.None;
        ActionToast = (toast, success);
        LastActionMessage = toast;
        var captured = toast;
        await Task.Delay(4000);
        if (ActionToast?.Text == captured) ActionToast = null;
    }

    private static Task StepDelay() => Task.Delay(250);

    public async void ForceSyncLog()
    {
        if (RunningAction != RunningAction.None) return;
        BeginAction(RunningAction.ForceSyncLog);
        ActionLog.Clear();
        LogStep("[INFO] Force Sync Log started…", ActionLogLevel.Info);
        await StepDelay();
        LogStep("[EXEC] Re-reading DaVinci Resolve log tail…");
        _logWatcher?.ForceSync();
        await StepDelay();
        LogStep("[SUCCESS] Log resynced.", ActionLogLevel.Success);
        EndAction(true, "Log resynced");
    }

    /// Cere confirmare userului ÎNAINTE de a șterge orice — Purge Cache e
    /// distructiv, `confirm` primește un callback pe care View-ul (dialogul
    /// de confirmare WPF) îl apelează cu true/false.
    public void RequestPurgeCache(Action<Action<bool>> confirm)
    {
        if (RunningAction != RunningAction.None) return;
        confirm(async approved =>
        {
            if (!approved) return;
            BeginAction(RunningAction.PurgeCache);
            ActionLog.Clear();
            LogStep("[INFO] Purge Cache started…", ActionLogLevel.Info);
            await StepDelay();
            var path = CacheFolderLocator.ActivePath;
            LogStep($"[INFO] Scanning cache folder: {path}", ActionLogLevel.Info);
            await StepDelay();
            var before = CacheFolderLocator.GetDiskInfo();
            if (before != null) LogStep($"[EXEC] {before.FreeGB:F1} GB free before purge…");
            try
            {
                int count = CacheFolderLocator.Purge();
                await StepDelay();
                LogStep($"[EXEC] Purged {count} item(s)…");
                CheckDisk();
                if (DiskInfo != null && before != null)
                {
                    var freed = Math.Max(DiskInfo.FreeGB - before.FreeGB, 0);
                    LogStep($"[SUCCESS] System Optimised — freed {freed:F1} GB.", ActionLogLevel.Success);
                }
                else
                {
                    LogStep("[SUCCESS] Purge Cache completed successfully!", ActionLogLevel.Success);
                }
                EndAction(true, $"Purged {count} item(s) from cache");
            }
            catch (Exception ex)
            {
                LogStep($"[ERROR] Purge failed: {ex.Message}", ActionLogLevel.Error);
                EndAction(false, "Purge failed");
            }
        });
    }

    public async void OptimiseSystem()
    {
        if (RunningAction != RunningAction.None) return;
        BeginAction(RunningAction.OptimiseSystem);
        ActionLog.Clear();
        LogStep("[INFO] Optimise System started…", ActionLogLevel.Info);
        await StepDelay();
        LogStep("[EXEC] Re-reading DaVinci Resolve log tail…");
        _logWatcher?.ForceSync();
        await StepDelay();
        LogStep("[EXEC] Recalculating CacheClip disk usage…");
        CheckDisk();
        await StepDelay();
        if (DiskInfo is { } disk)
            LogStep($"[INFO] {disk.FreeGB:F1} GB free on {disk.Path}");
        LogStep("[SUCCESS] System check refreshed.", ActionLogLevel.Success);
        EndAction(true, "System check refreshed");
    }
}
