using System;
using System.Runtime.InteropServices;

namespace MediaFlowMonitor.Overlay;

[Flags]
public enum HotkeyModifiers { None = 0, Alt = 1, Control = 2, Shift = 4, Win = 8 }

/// Wrapper peste RegisterHotKey (User32) — echivalentul nativ Windows
/// al Carbon HotKey API folosit pe macOS. Necesită un HWND de mesaje.
public sealed class GlobalHotkey : IDisposable
{
    [DllImport("user32.dll")]
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll")]
    private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    private const int HotkeyId = 0x4D46; // "MF"
    private readonly IntPtr _hwnd;

    public event EventHandler? Pressed;

    public GlobalHotkey(HotkeyModifiers modifiers, uint key, IntPtr hwnd = default)
    {
        _hwnd = hwnd;
        RegisterHotKey(_hwnd, HotkeyId, (uint)modifiers, key);
        // NOTĂ: procesarea mesajului WM_HOTKEY (0x0312) se face în WndProc-ul
        // ferestrei de mesaje asociate _hwnd — de conectat la message pump-ul WinUI.
    }

    internal void RaisePressed() => Pressed?.Invoke(this, EventArgs.Empty);

    public void Dispose() => UnregisterHotKey(_hwnd, HotkeyId);
}
