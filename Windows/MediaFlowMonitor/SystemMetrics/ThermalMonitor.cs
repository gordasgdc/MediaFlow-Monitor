using System;
using System.Linq;
using System.Management;

namespace MediaFlowMonitor.SystemMetrics;

public enum ThermalState { Unknown, Nominal, Fair, Serious, Critical }

public static class ThermalStateExtensions
{
    public static string Label(this ThermalState state) => state switch
    {
        ThermalState.Nominal => "Normal",
        ThermalState.Fair => "Ridicat",
        ThermalState.Serious => "Serios (throttling probabil)",
        ThermalState.Critical => "Critic (throttling activ)",
        _ => "Necunoscut pe acest PC",
    };

    public static MetricLevel Level(this ThermalState state) => state switch
    {
        ThermalState.Fair => MetricLevel.Warning,
        ThermalState.Serious or ThermalState.Critical => MetricLevel.Critical,
        _ => MetricLevel.Ok, // Unknown NU alarmeaza - vezi nota din ThermalMonitor.
    };
}

/// DECIZIE DE ARHITECTURĂ (2026-08-31), simetrică cu `ThermalMonitor.swift`
/// (Mac): Windows nu are un echivalent al `ProcessInfo.thermalState` — nicio
/// stare de throttling documentată public, la nivel de OS. Singura sursă
/// standard e `MSAcpi_ThermalZoneTemperature` (namespace WMI `root\WMI`),
/// care raportează temperatura reală a zonei ACPI — DAR multe placi de bază
/// (mai ales desktop-uri) nu implementează deloc acest sensor ACPI, caz în
/// care interogarea întoarce 0 rezultate (nu o eroare). Onest, ca la VRAM:
/// dacă senzorul lipsește, starea rămâne `Unknown` ("Necunoscut pe acest
/// PC"), NU e tratată ca alarmă (Level = Ok) — un PC fără acest senzor nu
/// trebuie să pară fals "sănătos" în text, dar nici nu trebuie să declanșeze
/// bannere pe baza unei lipse de date.
public sealed class ThermalMonitor : IDisposable
{
    public event EventHandler<ThermalState>? StateChanged;

    private System.Threading.Timer? _timer;
    private ThermalState _lastState = ThermalState.Unknown;

    public void Start()
    {
        Tick();
        _timer = new System.Threading.Timer(_ => Tick(), null, TimeSpan.FromSeconds(10), TimeSpan.FromSeconds(10));
    }

    public void Stop()
    {
        _timer?.Dispose();
        _timer = null;
    }

    public void Dispose() => Stop();

    private void Tick()
    {
        var celsius = TryReadTemperatureCelsius();
        var state = celsius switch
        {
            null => ThermalState.Unknown,
            > 95 => ThermalState.Critical,
            > 88 => ThermalState.Serious,
            > 78 => ThermalState.Fair,
            _ => ThermalState.Nominal,
        };
        if (state != _lastState)
        {
            _lastState = state;
            StateChanged?.Invoke(this, state);
        }
    }

    private static double? TryReadTemperatureCelsius()
    {
        try
        {
            using var searcher = new ManagementObjectSearcher(@"root\WMI", "SELECT CurrentTemperature FROM MSAcpi_ThermalZoneTemperature");
            using var results = searcher.Get();
            // Tempuri raportate in zecimi de Kelvin - luam cea mai fierbinte
            // zona ACPI disponibila (cea mai relevanta pentru throttling).
            var maxTenthsKelvin = results.Cast<ManagementBaseObject>()
                .Select(o => Convert.ToDouble(o["CurrentTemperature"]))
                .DefaultIfEmpty(-1)
                .Max();
            if (maxTenthsKelvin <= 0) return null;
            return maxTenthsKelvin / 10.0 - 273.15;
        }
        catch
        {
            return null; // WMI/ACPI indisponibil pe acest PC - degradare graţioasă, nu crash.
        }
    }
}
