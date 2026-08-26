using System;
using System.Collections.Generic;

namespace MediaFlowMonitor.Overlay;

public readonly record struct HistoryPoint(DateTime Date, double Value);

/// Ring-buffer pentru seriile de timp din grafice — echivalentul
/// MetricsHistory.swift de pe Mac, capacitate fixă (nu crește nemărginit).
public sealed class MetricsHistory
{
    private readonly int _capacity;
    private readonly List<HistoryPoint> _points = new();

    public IReadOnlyList<HistoryPoint> Points => _points;

    public MetricsHistory(int capacity = 120) => _capacity = capacity;

    public void Append(double value, DateTime? at = null)
    {
        _points.Add(new HistoryPoint(at ?? DateTime.Now, value));
        if (_points.Count > _capacity)
            _points.RemoveRange(0, _points.Count - _capacity);
    }
}
