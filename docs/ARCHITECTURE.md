# MediaFlow Monitor — Arhitectură

## Viziune
Utilitar ultra-lightweight de monitorizare + diagnosticare DaVinci Resolve în timp real. Zero Electron, zero overhead vizibil asupra procesării media.

## Platforme (cod nativ separat)

| | macOS | Windows |
|---|---|---|
| UI | SwiftUI + `NSPanel` | WinUI 3 (`Window` + Acrylic) |
| Monitorizare | Combine | Events (C#) |
| Log watch | `FSEventStream` | `FileSystemWatcher` |
| RAM/Swap | `host_statistics64` + `sysctlbyname` | `PerformanceCounter` |
| Hotkey global | Carbon `RegisterEventHotKey` (Cmd+Shift+M) | User32 `RegisterHotKey` (Ctrl+Shift+M) |
| Localizare | `.strings` (`Bundle.module`) | `.resx` |
| Packaging | SPM, unsigned/ad-hoc | MSIX/self-contained, unsigned |

## Decizii de performanță (zero overhead)
1. **Event-driven, nu polling** — FSEvents/FileSystemWatcher notifică la scriere; nu se citește fișierul decât la eveniment.
2. **Tail-only read** — offset salvat per platformă; niciodată nu se recitește tot log-ul.
3. **Interval adaptiv** — 3s idle / 1s când timeline-ul e activ, cu leeway mare pe timer (reduce trezirile CPU).
4. **API native de sistem**, nu subprocese/WMI greu — `host_statistics64` (Mach) și `PerformanceCounter` (nu WMI query).
5. **Overlay ascuns implicit**, randare doar la schimbare de stare (SwiftUI diffing / WinUI binding), fără re-render pe tick.
6. **Fără Dock icon / fără fereastră principală** — `LSUIElement`/`.accessory` pe macOS; echivalent pe Windows (fără taskbar entry, doar tray + overlay).

## Semnale extrase din log-uri DaVinci Resolve
- Plugin OFX/VST crash
- GPU Memory Full
- Dropped frames (I/O)
- Render Cache regenerated (cache invalid)
- Fusion comp render time > prag (predictor blocaj)
- Codec decode fallback to software
- Database connection lost (proiecte colaborative)

## Structură repo
```
MediaFlow-Monitor/
├── macOS/MediaFlowMonitor/     (SPM, Swift)
├── Windows/MediaFlowMonitor/   (.csproj, C#/WinUI 3)
├── Resources/Localization/     (sursă .strings, oglindite în ambele target-uri)
└── docs/ARCHITECTURE.md
```

## Stare curentă
- macOS: build local verificat ✅, localizare RO/EN/ES funcțională ✅.
- Windows: skeleton scris, **neconstruit** (fără mediu Windows disponibil aici).

## TODO tehnice — fază de testare
- [ ] **Windows**: conectare `WM_HOTKEY` la message pump-ul WinUI (necesită `HWND` dedicat prin `Win32Interop.GetWindowFromWindowHandle` sau fereastră de mesaje ascunsă).
- [ ] **Windows**: primul build/test real pe mașină Windows (`dotnet build`), validare `PerformanceCounter` are drepturi de citire fără elevare.
- [ ] **macOS**: implementare `VRAMProbe.swift` (IOKit `IOAccelerator` stats) — VRAM e `nil` momentan.
- [ ] **Ambele**: acțiuni reale pentru `[Purge Cache]` / `[Bypass FX]` (azi: placeholder, `suggestedAction = nil`).
- [ ] **Ambele**: buton `[Reveal Cache Folder]` — cheie de localizare există, acțiune neimplementată.
- [ ] Testare regex-uri de parsare log pe exemple reale de log DaVinci (formatele curente sunt presupuse, nevalidate pe fișiere reale).
- [ ] Test consum CPU/RAM real (target: <0.5% CPU, <30MB RAM) pe sesiune lungă de editare.
- [ ] Semnare/Notarization — explicit amânat până la stabilizare (conform fazei curente).
