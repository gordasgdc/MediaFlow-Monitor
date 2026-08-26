using System;
using System.IO;
using System.Linq;
using System.Management;
using Microsoft.Win32;

namespace MediaFlowMonitor.SystemMetrics;

public sealed record DiskInfo(string Path, double UsedGB, double TotalGB, double FreeGB, bool? IsHealthy);

/// Echivalentul Windows al CacheFolderLocator.swift — aceeași euristică
/// onestă (DaVinci Resolve nu expune public calea reală de "Cache Files
/// Location"): verifică locația implicită, apoi scanează toate discurile
/// montate (inclusiv externe USB/Thunderbolt) după un folder "CacheClip".
/// Selecția manuală (FolderBrowserDialog) rămâne obligatorie pentru
/// workflow-uri profesionale, la fel ca pe Mac.
public static class CacheFolderLocator
{
    private const string RegistryKey = @"Software\GDC\MediaFlowMonitor";
    private const string OverrideValueName = "CachePathOverride";

    public static string ActivePath
    {
        get
        {
            var saved = ReadOverride();
            if (saved != null && Directory.Exists(saved)) return saved;
            return AutoDetectedPath;
        }
    }

    public static bool IsManualOverride => ReadOverride() != null;

    private static string AutoDetectedPath
    {
        get
        {
            var defaultLocal = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                "Blackmagic Design", "DaVinci Resolve", "CacheClip");
            if (Directory.Exists(defaultLocal)) return defaultLocal;

            // Scanează toate discurile READY (inclusiv externe USB/Thunderbolt
            // montate ca literă de disc pe Windows) după un folder "CacheClip".
            foreach (var drive in DriveInfo.GetDrives().Where(d => d.IsReady))
            {
                var candidate = Path.Combine(drive.RootDirectory.FullName, "CacheClip");
                if (Directory.Exists(candidate)) return candidate;
            }
            return defaultLocal;
        }
    }

    /// Deschide un selector de folder nativ — necesită System.Windows.Forms
    /// (deja referențiat via UseWindowsForms=true în .csproj pentru NotifyIcon).
    public static string? ChooseFolderManually()
    {
        using var dialog = new System.Windows.Forms.FolderBrowserDialog
        {
            Description = "Selectează folderul CacheClip (poate fi pe orice disc extern conectat)",
            ShowNewFolderButton = false,
        };
        if (dialog.ShowDialog() != System.Windows.Forms.DialogResult.OK) return null;
        WriteOverride(dialog.SelectedPath);
        return dialog.SelectedPath;
    }

    public static void ClearManualOverride()
    {
        using var key = Registry.CurrentUser.OpenSubKey(RegistryKey, writable: true);
        key?.DeleteValue(OverrideValueName, throwOnMissingValue: false);
    }

    /// Info de disc pentru volumul care conține ActivePath — funcționează
    /// identic pentru disc intern SAU extern (DriveInfo interoghează
    /// volumul montat, indiferent de conexiunea fizică).
    public static DiskInfo? GetDiskInfo()
    {
        var path = Directory.Exists(ActivePath)
            ? ActivePath
            : Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);

        try
        {
            var root = Path.GetPathRoot(Path.GetFullPath(path));
            if (root == null) return null;
            var drive = new DriveInfo(root);
            if (!drive.IsReady) return null;

            double totalGB = drive.TotalSize / 1_073_741_824.0;
            double freeGB = drive.AvailableFreeSpace / 1_073_741_824.0;
            double usedGB = Math.Max(totalGB - freeGB, 0);

            return new DiskInfo(path, usedGB, totalGB, freeGB, TryReadHealth(drive));
        }
        catch { return null; }
    }

    /// Best-effort, la fel de onest ca pe Mac (diskutil): citește Win32_DiskDrive
    /// Status — multe RAID-uri/adaptoare externe nu expun SMART standard,
    /// caz în care întoarce null (necunoscut), nu fals-pozitiv.
    private static bool? TryReadHealth(DriveInfo drive)
    {
        try
        {
            using var searcher = new ManagementObjectSearcher("SELECT Status FROM Win32_DiskDrive");
            foreach (ManagementObject disk in searcher.Get())
            {
                if (disk["Status"] is string status)
                {
                    if (status == "OK") return true;
                    if (status is "Pred Fail" or "Error" or "Bad") return false;
                }
            }
        }
        catch { /* WMI indisponibil sau fără drepturi — necunoscut, nu eroare */ }
        return null;
    }

    /// Purge REAL — șterge conținutul folderului CacheClip activ. Apelantul
    /// TREBUIE să confirme cu userul înainte (identic cu regula de pe Mac).
    public static int Purge()
    {
        var path = ActivePath;
        if (!Directory.Exists(path)) return 0;
        var entries = Directory.GetFileSystemEntries(path);
        foreach (var entry in entries)
        {
            if (Directory.Exists(entry)) Directory.Delete(entry, recursive: true);
            else File.Delete(entry);
        }
        return entries.Length;
    }

    private static string? ReadOverride()
    {
        using var key = Registry.CurrentUser.OpenSubKey(RegistryKey);
        return key?.GetValue(OverrideValueName) as string;
    }

    private static void WriteOverride(string path)
    {
        using var key = Registry.CurrentUser.CreateSubKey(RegistryKey);
        key.SetValue(OverrideValueName, path);
    }
}
