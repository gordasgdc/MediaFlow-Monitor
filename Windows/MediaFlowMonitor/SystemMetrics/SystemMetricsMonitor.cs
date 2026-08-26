using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Threading;

namespace MediaFlowMonitor.SystemMetrics;

public enum MetricLevel { Ok, Warning, Critical }

public readonly record struct MemorySnapshot(
    double RamUsedGB, double RamTotalGB,
    double SwapUsedGB, MetricLevel SwapLevel,
    double? VramUsedGB, double[] CpuPerCore,
    List<ProcessUsage> TopRamProcesses, List<ProcessUsage> TopSwapProcesses);

/// Citește RAM/Swap via PerformanceCounters, VRAM prin WMI (best-effort —
/// Win32_VideoController.AdapterRAM e cunoscut plafonat la ~4GB pe unele
/// drivere/OS-uri, exact ca IOKit-ul de pe Mac, degradează la null dacă nu
/// se poate citi), CPU per-core prin PerformanceCounter pe fiecare instanță
/// "Processor" (nu "Processor Information", identic ca semantică cu
/// host_processor_info de pe Mac).
public sealed class SystemMetricsMonitor : IDisposable
{
    private PerformanceCounter? _committedBytesCounter;
    private List<PerformanceCounter>? _coreCounters;
    private List<PerformanceCounter>? _vramUsageCounters;
    private System.Threading.Timer? _timer;
    private double _lastSwapUsed;

    private readonly TimeSpan _idleInterval = TimeSpan.FromSeconds(3);
    private readonly TimeSpan _activeInterval = TimeSpan.FromSeconds(1);
    public bool IsTimelineActive { get; set; }

    public event EventHandler<MemorySnapshot>? SnapshotReady;

    public void Start()
    {
        _committedBytesCounter = new PerformanceCounter("Memory", "Committed Bytes");

        var cat = new PerformanceCounterCategory("Processor");
        _coreCounters = cat.GetInstanceNames()
            .Where(n => n != "_Total")
            .OrderBy(n => int.TryParse(n, out var i) ? i : int.MaxValue)
            .Select(n => new PerformanceCounter("Processor", "% Processor Time", n))
            .ToList();
        // prima citire pe un PerformanceCounter de tip "% ..." e mereu 0 —
        // "amorsăm" contorul, la fel ca CPUMonitor.perCoreUsage() (delta) pe Mac.
        foreach (var c in _coreCounters) c.NextValue();

        // "GPU Adapter Memory" — categorie de contoare built-in din DXGI
        // (Windows 10 1903+), disponibilă fără niciun SDK de vendor
        // (NVML/ADL). "Dedicated Usage" per instanță = VRAM chiar folosit
        // acum, mult mai fiabil decât Win32_VideoController.AdapterRAM
        // (cunoscut plafonat la ~4GB pe multe drivere moderne).
        try
        {
            if (PerformanceCounterCategory.Exists("GPU Adapter Memory"))
            {
                var gpuCat = new PerformanceCounterCategory("GPU Adapter Memory");
                _vramUsageCounters = gpuCat.GetInstanceNames()
                    .Select(n => new PerformanceCounter("GPU Adapter Memory", "Dedicated Usage", n))
                    .ToList();
            }
        }
        catch { _vramUsageCounters = null; }

        _timer = new System.Threading.Timer(_ => Tick(), null, TimeSpan.Zero, IsTimelineActive ? _activeInterval : _idleInterval);
    }

    public void Stop()
    {
        _timer?.Dispose();
        _committedBytesCounter?.Dispose();
        _coreCounters?.ForEach(c => c.Dispose());
        _vramUsageCounters?.ForEach(c => c.Dispose());
    }

    public void Dispose() => Stop();

    private void Tick()
    {
        if (_committedBytesCounter == null) return;

        // BUG FIX (2026-08-26): folosea Environment.WorkingSet — memoria
        // PROCESULUI aplicației, nu RAM-ul de sistem. GC.GetGCMemoryInfo()
        // dă capacitatea totală corectă; RAM-ul folosit se calculează din
        // Commit - la fel cum era deja folosit pentru swap, dar corect
        // separat aici prin "Memory\Available Bytes".
        var gcInfo = GC.GetGCMemoryInfo();
        double ramTotalGB = gcInfo.TotalAvailableMemoryBytes / 1_073_741_824.0;

        double? availableGB = TryReadAvailableMemoryGB();
        double ramUsedGB = availableGB.HasValue ? Math.Max(0, ramTotalGB - availableGB.Value) : 0;

        double committedGB = _committedBytesCounter.NextValue() / 1_073_741_824.0;
        double swapUsedGB = Math.Max(0, committedGB - ramTotalGB);
        double delta = swapUsedGB - _lastSwapUsed;
        _lastSwapUsed = swapUsedGB;

        var level = swapUsedGB > 4.0 || delta > 0.5 ? MetricLevel.Critical
            : swapUsedGB > 1.0 || delta > 0.1 ? MetricLevel.Warning
            : MetricLevel.Ok;

        double[] cpuPerCore = _coreCounters?
            .Select(c => { try { return c.NextValue() / 100.0; } catch { return 0.0; } })
            .ToArray() ?? Array.Empty<double>();

        double? vramUsedGB = null;
        if (_vramUsageCounters is { Count: > 0 })
        {
            try
            {
                double totalBytes = _vramUsageCounters.Sum(c => c.NextValue());
                vramUsedGB = totalBytes / 1_073_741_824.0;
            }
            catch { vramUsedGB = null; }
        }

        var (topRam, topSwap) = ProcessInspector.TopProcesses();
        SnapshotReady?.Invoke(this, new MemorySnapshot(ramUsedGB, ramTotalGB, swapUsedGB, level, vramUsedGB, cpuPerCore, topRam, topSwap));

        _timer?.Change(IsTimelineActive ? _activeInterval : _idleInterval, IsTimelineActive ? _activeInterval : _idleInterval);
    }

    private static double? TryReadAvailableMemoryGB()
    {
        try
        {
            using var counter = new PerformanceCounter("Memory", "Available Bytes");
            return counter.NextValue() / 1_073_741_824.0;
        }
        catch { return null; }
    }

}
