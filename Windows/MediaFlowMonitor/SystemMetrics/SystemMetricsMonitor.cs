using System;
using System.Diagnostics;
using System.Threading;

namespace MediaFlowMonitor.SystemMetrics;

public enum MetricLevel { Ok, Warning, Critical }

public readonly record struct MemorySnapshot(
    double RamUsedGB, double RamTotalGB,
    double SwapUsedGB, MetricLevel SwapLevel);

/// Citește RAM/Swap via PerformanceCounters (nativ, fără WMI — WMI e mult mai
/// costisitor per query). VRAM rămâne TODO (necesită vendor API: NVML/ADL).
public sealed class SystemMetricsMonitor : IDisposable
{
    private PerformanceCounter? _committedBytesCounter;
    private PerformanceCounter? _commitLimitCounter;
    private Timer? _timer;
    private double _lastSwapUsed;

    private readonly TimeSpan _idleInterval = TimeSpan.FromSeconds(3);
    private readonly TimeSpan _activeInterval = TimeSpan.FromSeconds(1);
    public bool IsTimelineActive { get; set; }

    public event EventHandler<MemorySnapshot>? SnapshotReady;

    public void Start()
    {
        _committedBytesCounter = new PerformanceCounter("Memory", "Committed Bytes");
        _commitLimitCounter = new PerformanceCounter("Memory", "Commit Limit");

        _timer = new Timer(_ => Tick(), null, TimeSpan.Zero, IsTimelineActive ? _activeInterval : _idleInterval);
    }

    public void Stop()
    {
        _timer?.Dispose();
        _committedBytesCounter?.Dispose();
        _commitLimitCounter?.Dispose();
    }

    public void Dispose() => Stop();

    private void Tick()
    {
        if (_committedBytesCounter == null || _commitLimitCounter == null) return;

        var gcInfo = GC.GetGCMemoryInfo();
        double ramTotalGB = gcInfo.TotalAvailableMemoryBytes / 1_073_741_824.0;

        using var proc = Process.GetCurrentProcess();
        double ramUsedGB = Environment.WorkingSet / 1_073_741_824.0;

        double committedGB = _committedBytesCounter.NextValue() / 1_073_741_824.0;
        double commitLimitGB = _commitLimitCounter.NextValue() / 1_073_741_824.0;
        // "Swap used" aproximat: commit peste RAM fizică disponibilă
        double swapUsedGB = Math.Max(0, committedGB - ramTotalGB);
        double delta = swapUsedGB - _lastSwapUsed;
        _lastSwapUsed = swapUsedGB;

        var level = swapUsedGB > 4.0 || delta > 0.5 ? MetricLevel.Critical
            : swapUsedGB > 1.0 || delta > 0.1 ? MetricLevel.Warning
            : MetricLevel.Ok;

        SnapshotReady?.Invoke(this, new MemorySnapshot(ramUsedGB, ramTotalGB, swapUsedGB, level));

        // reprogramează intervalul dacă s-a schimbat starea timeline-ului
        _timer?.Change(IsTimelineActive ? _activeInterval : _idleInterval, IsTimelineActive ? _activeInterval : _idleInterval);
    }
}
