using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;

namespace MediaFlowMonitor.SystemMetrics;

public readonly record struct ProcessUsage(int Pid, string Name, double ValueGB);

/// Top consumatori de RAM/Swap per proces.
///
/// Spre deosebire de macOS (fără câmp public de "swap per proces" — vezi
/// comentariul din ProcessInspector.swift), Windows chiar expune date REALE:
/// `Process.PagedMemorySize64` e octeții din spațiul de adrese al procesului
/// susținuți efectiv de fișierul de paginare (pagefile.sys) — echivalentul
/// direct al coloanei "Commit Size" din Resource Monitor.
public static class ProcessInspector
{
    public static (List<ProcessUsage> Ram, List<ProcessUsage> Swap) TopProcesses(int limit = 3)
    {
        var ram = new List<ProcessUsage>();
        var swap = new List<ProcessUsage>();

        foreach (var process in Process.GetProcesses())
        {
            using (process)
            {
                try
                {
                    double residentGB = process.WorkingSet64 / 1_073_741_824.0;
                    if (residentGB > 0.01)
                        ram.Add(new ProcessUsage(process.Id, process.ProcessName, residentGB));

                    double pagedGB = process.PagedMemorySize64 / 1_073_741_824.0;
                    if (pagedGB > 0.01)
                        swap.Add(new ProcessUsage(process.Id, process.ProcessName, pagedGB));
                }
                catch
                {
                    // Access denied (procese de sistem/alt user) - sarim peste, nu blocam scanarea.
                }
            }
        }

        return (
            ram.OrderByDescending(p => p.ValueGB).Take(limit).ToList(),
            swap.OrderByDescending(p => p.ValueGB).Take(limit).ToList()
        );
    }

    // MARK: - NLE activ (paritate cu ProcessInspector.swift)

    public readonly record struct NLEProcess(string Name, int Pid, double RamGB);

    /// Numele sub care ruleaza efectiv procesele, nu cele din meniul Start.
    /// Potrivire pe fragment, insensibila la majuscule: versiunile difera
    /// („Resolve", „Adobe Premiere Pro 2026"), dar fragmentul ramane.
    private static readonly (string Fragment, string Label)[] NleMarkers =
    {
        ("resolve", "DaVinci Resolve"),
        ("premiere", "Adobe Premiere Pro"),
        ("afterfx", "After Effects"),
        ("mediacomposer", "Avid Media Composer"),
        ("vegas", "VEGAS Pro"),
    };

    /// Aplicatia de montaj activa, daca ruleaza vreuna.
    ///
    /// Se accepta DOAR procesele cu fereastra principala (MainWindowHandle
    /// nenul) — acelasi criteriu ca `activationPolicy == .regular` pe macOS:
    /// un helper de fundal Adobe nu inseamna ca cineva monteaza, iar
    /// badge-ul ar minti.
    public static NLEProcess? ActiveNLE()
    {
        foreach (var process in Process.GetProcesses())
        {
            using (process)
            {
                try
                {
                    string name = process.ProcessName.ToLowerInvariant();
                    var match = NleMarkers.FirstOrDefault(m => name.Contains(m.Fragment, StringComparison.Ordinal));
                    if (match.Label is null) continue;
                    if (process.MainWindowHandle == IntPtr.Zero) continue;
                    return new NLEProcess(match.Label, process.Id, process.WorkingSet64 / 1_073_741_824.0);
                }
                catch
                {
                    // Access denied sau proces iesit intre timp — sarim peste.
                }
            }
        }
        return null;
    }

    // MARK: - DaVinci Resolve zombie detection

    private static List<Process> DavinciProcesses() =>
        Process.GetProcesses().Where(p => p.ProcessName.Contains("Resolve", StringComparison.OrdinalIgnoreCase)).ToList();

    /// True daca exista cel putin un proces "Resolve" cu fereastra vizibila
    /// (MainWindowHandle nenul) - semn ca userul chiar lucreaza in Resolve,
    /// nu ca a mai ramas doar un proces agatat in fundal.
    public static bool IsDaVinciResolveWindowVisible()
    {
        var procs = DavinciProcesses();
        try { return procs.Any(p => { try { return p.MainWindowHandle != IntPtr.Zero; } catch { return false; } }); }
        finally { foreach (var p in procs) p.Dispose(); }
    }

    public static bool AnyDaVinciProcessRunning()
    {
        var procs = DavinciProcesses();
        try { return procs.Count > 0; }
        finally { foreach (var p in procs) p.Dispose(); }
    }

    /// Force Close Hanging DaVinci - kill imediat pe orice proces "Resolve"
    /// gasit. Intoarce numarul de procese omorate.
    public static int ForceKillHangingDaVinci()
    {
        var procs = DavinciProcesses();
        int count = 0;
        foreach (var p in procs)
        {
            using (p)
            {
                try { p.Kill(); count++; }
                catch { /* deja iesit intre timp, sau access denied */ }
            }
        }
        return count;
    }
}
