using System;
using System.Runtime.InteropServices;

namespace MediaFlowMonitor.Overlay;

[Flags]
public enum HotkeyModifiers { None = 0, Alt = 1, Control = 2, Shift = 4, Win = 8 }

/// Wrapper peste RegisterHotKey (User32) — echivalentul nativ Windows
/// al Carbon HotKey API folosit pe macOS.
///
/// FIX (2026-08-26): RegisterHotKey cu hwnd=IntPtr.Zero trimite WM_HOTKEY
/// ca mesaj de THREAD, nu de fereastră — dar WinUI3 nu rulează un
/// GetMessage/DispatchMessage clasic peste care să-l intercepți (nu are
/// niciun hook expus pentru mesajele de thread). Soluție: creăm o
/// fereastră Win32 ADEVĂRATĂ, ascunsă, de tip "message-only"
/// (HWND_MESSAGE), cu propriul WndProc — DispatchMessage rutează
/// WM_HOTKEY către WndProc-ul ferestrei ȚINTĂ a RegisterHotKey,
/// indiferent care thread rulează pompa de mesaje (thread-ul UI WinUI3
/// chiar rulează un message loop Win32 standard, sub capotă — verificat:
/// funcționează pentru orice fereastră creată pe același thread).
public sealed class GlobalHotkey : IDisposable
{
    private const int WM_HOTKEY = 0x0312;
    private const int WM_DESTROY = 0x0002;
    private const int HWND_MESSAGE = -3;
    private const int GWLP_WNDPROC = -4;

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern ushort RegisterClassEx(ref WNDCLASSEX lpwcx);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr CreateWindowEx(
        int dwExStyle, string lpClassName, string lpWindowName, int dwStyle,
        int x, int y, int nWidth, int nHeight,
        IntPtr hWndParent, IntPtr hMenu, IntPtr hInstance, IntPtr lpParam);

    [DllImport("user32.dll")]
    private static extern IntPtr DefWindowProc(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern bool DestroyWindow(IntPtr hWnd);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr GetModuleHandle(string? lpModuleName);

    private delegate IntPtr WndProcDelegate(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct WNDCLASSEX
    {
        public int cbSize;
        public int style;
        public WndProcDelegate lpfnWndProc;
        public int cbClsExtra;
        public int cbWndExtra;
        public IntPtr hInstance;
        public IntPtr hIcon;
        public IntPtr hCursor;
        public IntPtr hbrBackground;
        public string? lpszMenuName;
        public string lpszClassName;
        public IntPtr hIconSm;
    }

    private const int HotkeyId = 0x4D46; // "MF"
    private readonly IntPtr _hwnd;
    // Ținem delegate-ul viu (GC-rooted) cât timp fereastra există — altfel
    // marshalling-ul native poate elibera delegate-ul și WndProc-ul crapă
    // la primul apel (capcană clasică P/Invoke cu callback-uri).
    private readonly WndProcDelegate _wndProc;

    public event EventHandler? Pressed;

    public GlobalHotkey(HotkeyModifiers modifiers, uint key)
    {
        _wndProc = WndProc;
        var className = "MediaFlowMonitorHotkeyWnd_" + Guid.NewGuid().ToString("N");
        var hInstance = GetModuleHandle(null);

        var wc = new WNDCLASSEX
        {
            cbSize = Marshal.SizeOf<WNDCLASSEX>(),
            lpfnWndProc = _wndProc,
            hInstance = hInstance,
            lpszClassName = className,
        };
        RegisterClassEx(ref wc);

        _hwnd = CreateWindowEx(0, className, "", 0, 0, 0, 0, 0, new IntPtr(HWND_MESSAGE), IntPtr.Zero, hInstance, IntPtr.Zero);
        if (_hwnd != IntPtr.Zero)
        {
            RegisterHotKey(_hwnd, HotkeyId, (uint)modifiers, key);
        }
    }

    private IntPtr WndProc(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam)
    {
        if (msg == WM_HOTKEY && wParam.ToInt32() == HotkeyId)
        {
            Pressed?.Invoke(this, EventArgs.Empty);
            return IntPtr.Zero;
        }
        return DefWindowProc(hWnd, msg, wParam, lParam);
    }

    public void Dispose()
    {
        if (_hwnd != IntPtr.Zero)
        {
            UnregisterHotKey(_hwnd, HotkeyId);
            DestroyWindow(_hwnd);
        }
    }
}
