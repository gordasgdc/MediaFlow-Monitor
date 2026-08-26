using System;
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
public enum RunningAction { None, PurgeCache, ForceSyncLog, OptimiseSystem }

public sealed record LogConsoleEntry(DateTime Date, string Text, MetricLevel Level);
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

    public ObservableCollection<LogConsoleEntry> LogConsole { get; } = new();
    public ObservableCollection<Recommendation> Recommendations { get; } = new();
    public ObservableCollection<ActionLogEntry> ActionLog { get; } = new();

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
        _diskCheckTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(60) };
        _diskCheckTimer.Tick += (_, _) => CheckDisk();
        _diskCheckTimer.Start();
    }

    private void CheckDisk()
    {
        DiskInfo = CacheFolderLocator.GetDiskInfo();
        UpdateRecommendations();
    }

    private void Apply(MemorySnapshot snapshot)
    {
        RamFraction = Math.Min(snapshot.RamUsedGB / Math.Max(snapshot.RamTotalGB, 1), 1);
        SwapFraction = Math.Min(snapshot.SwapUsedGB / 8.0, 1);
        VramUsedGB = snapshot.VramUsedGB;
        CpuPerCore = snapshot.CpuPerCore;
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

        UpdateRecommendations();
    }

    private static void SyncCollection(ObservableCollection<HistoryPoint> target, System.Collections.Generic.IReadOnlyList<HistoryPoint> source)
    {
        target.Clear();
        foreach (var p in source) target.Add(p);
    }

    private void Apply(ResolveLogSignal signal)
    {
        var (text, level) = signal.Kind switch
        {
            ResolveLogSignalKind.PluginCrash => ($"Plugin crashed: {signal.Detail}", MetricLevel.Critical),
            ResolveLogSignalKind.GpuMemoryFull => ("GPU Memory Full", MetricLevel.Critical),
            ResolveLogSignalKind.DroppedFrames => ($"Timeline dropped frame ({signal.Value})", MetricLevel.Warning),
            ResolveLogSignalKind.RenderCacheRegenerated => ("Render Cache invalid — regenerated", MetricLevel.Warning),
            ResolveLogSignalKind.FusionSlowNode => ($"Fusion composition slow rendering ({signal.Value}ms)", MetricLevel.Warning),
            ResolveLogSignalKind.CodecSoftwareFallback => ("Codec fallback to software decode", MetricLevel.Warning),
            ResolveLogSignalKind.DbConnectionLost => ("Database connection lost", MetricLevel.Critical),
            _ => ("Unknown signal", MetricLevel.Warning),
        };

        LogConsole.Insert(0, new LogConsoleEntry(DateTime.Now, text, level));
        while (LogConsole.Count > MaxConsoleLines) LogConsole.RemoveAt(LogConsole.Count - 1);
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

        if (LogConsole.Any(e => e.Level == MetricLevel.Critical))
            Recommendations.Add(new Recommendation("Recent critical event in DaVinci log — check console below", MetricLevel.Critical));

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
