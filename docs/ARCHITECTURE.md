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
- macOS: build local verificat ✅, semnat + notarizat Apple ✅, localizare RO/EN/ES ✅, licențiere + revocare Supabase ✅.
- Windows: **build reușit** ✅ (2026-08-26, pe Parallels/Windows 11, VS 2026 + .NET 10 SDK) — `.exe` pornește, dar overlay-ul e invizibil (vezi TODO hotkey mai jos). Fără licențiere/update checker/VRAM încă.

## Windows — pitfall de build cunoscut (rezolvat 2026-08-26)
`dotnet publish` eșua cu `MSB4062: Microsoft.Build.Packaging.Pri.Tasks.ExpandPriContent could not be loaded` — DLL-ul există doar în instalarea Visual Studio (workload **WinUI application development**, redenumit față de vechiul "Universal Windows Platform development"), nu în folderul SDK-ului `dotnet` CLI. Fix (o singură dată, PowerShell ca Administrator):
```powershell
$src = "C:\Program Files\Microsoft Visual Studio\<VS-ver>\Community\MSBuild\Microsoft\VisualStudio\v<VS-ver>.0\AppxPackage"
$dst = "C:\Program Files\dotnet\sdk\<SDK-ver>\Microsoft\VisualStudio\v<VS-ver>.0\AppxPackage"
New-Item -ItemType Directory -Force -Path $dst | Out-Null
Copy-Item "$src\*" $dst -Recurse -Force
```
`scripts/build-windows-exe.ps1` verifică acum automat prezența DLL-ului și avertizează dacă lipsește.

## TODO tehnice — fază de testare
- [ ] **Windows — CRITIC**: `WM_HOTKEY` nu ajunge nicăieri — `GlobalHotkey.RegisterHotKey` e apelat cu `hwnd=IntPtr.Zero` (mesaj de thread), dar WinUI3 nu rulează un `GetMessage`/`DispatchMessage` loop clasic peste care să-l intercepți. Rezultat confirmat: `.exe` pornește, dar Ctrl+Shift+M nu arată nimic — exact bug-ul deja reparat pe macOS (Automatic Termination), dar cu altă cauză. Necesită fereastră de mesaje ascunsă (`CreateWindowEx` + `WndProc` custom) sau folosirea unui `AppWindow`/`Win32Interop.GetWindowFromWindowHandle` real ca target al `RegisterHotKey`.
- [ ] **Windows**: licențiere (LicenseCore/MachineID), Update Checker, VRAM, alerte DaVinci în UI — toate există doar pe macOS.
- [ ] **macOS**: `Bypass FX` rămâne placeholder (necesită DaVinci Scripting API conectat).
- [ ] **Ambele**: acțiuni reale pentru `[Purge Cache]` / `[Bypass FX]` (azi: placeholder, `suggestedAction = nil`).
- [ ] **Ambele**: buton `[Reveal Cache Folder]` — cheie de localizare există, acțiune neimplementată.
- [ ] Testare regex-uri de parsare log pe exemple reale de log DaVinci (formatele curente sunt presupuse, nevalidate pe fișiere reale).
- [ ] Test consum CPU/RAM real (target: <0.5% CPU, <30MB RAM) pe sesiune lungă de editare.
- [ ] Semnare/Notarization — explicit amânat până la stabilizare (conform fazei curente).
