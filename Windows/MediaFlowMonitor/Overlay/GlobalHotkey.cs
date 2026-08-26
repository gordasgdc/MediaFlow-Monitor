using System;
using System.Runtime.InteropServices;
using System.Windows.Interop;

namespace MediaFlowMonitor.Overlay;

[Flags]
public enum HotkeyModifiers { None = 0, Alt = 1, Control = 2, Shift = 4, Win = 8 }

/// Wrapper peste RegisterHotKey (User32) — echivalentul nativ Windows
/// al Carbon HotKey API folosit pe macOS.
///
/// Mult mai simplu decat varianta WinUI3 (fereastra Win32 manuala cu
/// WndProc custom): WPF are deja HwndSource, care creeaza o fereastra
/// Win32 reala si integreaza AddHook direct in message pump-ul WPF
/// existent — pattern standard, documentat, folosit de ani de zile.
public sealed class GlobalHotkey : IDisposable
{
    private const int WM_HOTKEY = 0x0312;
    private const int HotkeyId = 0x4D46; // "MF"

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    private readonly HwndSource _source;

    public event EventHandler? Pressed;

    public GlobalHotkey(HotkeyModifiers modifiers, uint key)
    {
        var parameters = new HwndSourceParameters("MediaFlowMonitorHotkeyWindow")
        {
            Width = 0,
            Height = 0,
            WindowStyle = 0, // fara stiluri = fereastra ascunsa, niciodata aratata
        };
        _source = new HwndSource(parameters);
        _source.AddHook(WndProc);
        RegisterHotKey(_source.Handle, HotkeyId, (uint)modifiers, key);
    }

    private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == WM_HOTKEY && wParam.ToInt32() == HotkeyId)
        {
            Pressed?.Invoke(this, EventArgs.Empty);
            handled = true;
        }
        return IntPtr.Zero;
    }

    public void Dispose()
    {
        UnregisterHotKey(_source.Handle, HotkeyId);
        _source.Dispose();
    }
}
