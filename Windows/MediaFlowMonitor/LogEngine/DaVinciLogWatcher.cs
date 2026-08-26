using System;
using System.IO;
using System.Text.RegularExpressions;

namespace MediaFlowMonitor.LogEngine;

public enum ResolveLogSignalKind
{
    PluginCrash, GpuMemoryFull, DroppedFrames,
    RenderCacheRegenerated, FusionSlowNode, CodecSoftwareFallback, DbConnectionLost
}

public readonly record struct ResolveLogSignal(ResolveLogSignalKind Kind, string? Detail = null, int? Value = null);

/// Ascultă pasiv logurile DaVinci Resolve via FileSystemWatcher (event-driven,
/// echivalentul Windows al FSEventStream — zero polling).
public sealed class DaVinciLogWatcher : IDisposable
{
    private readonly string _logDirectory;
    private FileSystemWatcher? _watcher;
    private string? _activeLogPath;
    private long _lastOffset;

    public event EventHandler<ResolveLogSignal>? SignalDetected;

    public DaVinciLogWatcher()
    {
        _logDirectory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "Blackmagic Design", "DaVinci Resolve", "Support", "logs");
    }

    public void Start()
    {
        if (!Directory.Exists(_logDirectory)) return;

        _activeLogPath = FindLatestLogFile();
        if (_activeLogPath != null)
            _lastOffset = new FileInfo(_activeLogPath).Length;

        _watcher = new FileSystemWatcher(_logDirectory, "*.log")
        {
            NotifyFilter = NotifyFilters.LastWrite | NotifyFilters.Size,
            EnableRaisingEvents = true
        };
        _watcher.Changed += OnLogChanged;
    }

    public void Stop()
    {
        _watcher?.Dispose();
        _watcher = null;
    }

    public void Dispose() => Stop();

    private string? FindLatestLogFile()
    {
        var files = Directory.GetFiles(_logDirectory, "*.log");
        return files.Length == 0 ? null : files[Array.IndexOf(files, files.MaxBy(File.GetLastWriteTimeUtc))];
    }

    private void OnLogChanged(object sender, FileSystemEventArgs e)
    {
        if (_activeLogPath == null) _activeLogPath = e.FullPath;
        if (e.FullPath != _activeLogPath) return;

        try
        {
            using var stream = new FileStream(e.FullPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
            stream.Seek(_lastOffset, SeekOrigin.Begin);
            using var reader = new StreamReader(stream);
            string? line;
            while ((line = reader.ReadLine()) != null)
            {
                var signal = Parse(line);
                if (signal is { } s) SignalDetected?.Invoke(this, s);
            }
            _lastOffset = stream.Position;
        }
        catch (IOException)
        {
            // fișierul poate fi blocat momentan de Resolve — reîncercăm la următorul eveniment
        }
    }

    internal static ResolveLogSignal? Parse(string line)
    {
        if (line.Contains("GPU Memory Full"))
            return new ResolveLogSignal(ResolveLogSignalKind.GpuMemoryFull);
        if (line.Contains("Render Cache regenerated"))
            return new ResolveLogSignal(ResolveLogSignalKind.RenderCacheRegenerated);
        if (line.Contains("Database connection lost"))
            return new ResolveLogSignal(ResolveLogSignalKind.DbConnectionLost);
        if (line.Contains("decode fallback to software"))
            return new ResolveLogSignal(ResolveLogSignalKind.CodecSoftwareFallback);

        var crash = Regex.Match(line, @"OFX plugin .* crashed: (\w+)");
        if (crash.Success)
            return new ResolveLogSignal(ResolveLogSignalKind.PluginCrash, Detail: crash.Groups[1].Value);

        var dropped = Regex.Match(line, @"dropped (\d+) frames");
        if (dropped.Success)
            return new ResolveLogSignal(ResolveLogSignalKind.DroppedFrames, Value: int.Parse(dropped.Groups[1].Value));

        var fusion = Regex.Match(line, @"Fusion: comp render time (\d+)ms");
        if (fusion.Success)
            return new ResolveLogSignal(ResolveLogSignalKind.FusionSlowNode, Value: int.Parse(fusion.Groups[1].Value));

        return null;
    }
}
