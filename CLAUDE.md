# MediaFlow Monitor — reguli de arhitectură (Mac + Windows)

> **[SYSTEM DIRECTIVE FOR CLAUDE: DO NOT DELETE OR OVERWRITE EXISTING RULES. ONLY APPEND NEW RULES.]**
> Acest fișier e un jurnal viu, nu un document care se rescrie.

## [PARTEA 1: REGULI GLOBALE ECOSISTEM GDC] — mutată în `~/Developer/CLAUDE.md`

> Din 2026-09-18, regulile globale stau într-un singur fișier,
> `~/Developer/CLAUDE.md`, citit automat de Claude Code în orice proiect din
> `~/Developer/`. Nu se mai copiază aici. Ce era specific acestui repo în fosta
> Partea 1 (statusuri, excepții) e la finalul fișierului.

## [PARTEA 2: SPECIFICAȚII TEHNICE PROIECT]

## Structura repo-ului
- `macOS/MediaFlowMonitor/` — aplicația nativă SwiftUI/Combine (overlay Dashboard Pro, hotkey global Cmd+Shift+M, licențiere, update checker).
- `Windows/MediaFlowMonitor/` — port C#/WPF (net8.0-windows), hotkey Ctrl+Shift+M, tray icon via WinForms `NotifyIcon`.
- `dist/` — arhive de release (nu se comit binarele mari; doar `version-manifest.json`).
- `docs/` — landing page locală, superseded de pagina publică reală la `gordas.dev/media-flow-monitor` (repo `gdc-plugin-manager-catalog-vendor`).
- `installer/` — generator PDF ghid de utilizare (RO/EN/ES).
- `codesigning/` — semnare + notarizare Apple (identic cu restul ecosistemului).

## Technical Decisions & Known Pitfalls

- **2026-08-31 — GPU Monitor + Thermal Monitor (Mac + Windows, v1.9.0).**
  Nivel 1 pct. 2 și Nivel 3 pct. 10 din brainstorm-ul Master Control Studio
  Pro, mutate explicit pe MediaFlow Monitor (decizia lui Cristi).
  - **GPU Monitor**: pe Mac, extensie a `VRAMProbe.swift` existent —
    aceeași sursă `IOAccelerator`/`PerformanceStatistics`, cheia "Device
    Utilization %" (privată/nedocumentată, ca și VRAM — best-effort, nil
    dacă lipsește). Pe Windows, categoria de contoare built-in "GPU Engine"
    (DXGI, Win10 1903+), filtrată pe instanțe `engtype_3D` și însumată — e
    exact sursa graficului "GPU" din Task Manager, fără niciun SDK de
    vendor (NVML/ADL).
  - **Thermal Monitor**: DECIZIE DE ARHITECTURĂ — niciun raw-temperature
    citit prin SMC (Mac, nedocumentat/fragil) sau termen ACPI universal
    (Windows, adesea absent pe desktop-uri). Mac folosește
    `ProcessInfo.thermalState` — API PUBLIC, DOCUMENTAT, calculat de OS din
    senzorii reali, 4 stări (nominal/fair/serious/critical), expus prin
    `ThermalMonitor.swift` (nou) + `NotificationCenter` pe
    `thermalStateDidChangeNotification`. Windows nu are echivalent public —
    `ThermalMonitor.cs` (nou) încearcă `MSAcpi_ThermalZoneTemperature`
    (WMI `root\WMI`), cu un al 5-lea caz explicit `Unknown` (NU alarmă)
    când placa de bază nu expune senzorul ACPI — la fel de onest ca
    eticheta "Top Swap Activity" de pe Mac (proxy documentat, nu o valoare
    inventată sau falsă stare "sănătos").
  - UI: badge colorat + rând nou în panoul "System Health", grafic nou GPU
    (%) lângă VRAM/Swap și CPU, recomandare + notificare nativă
    (`UNUserNotificationCenter`/`NotifyIcon`) când starea termică ajunge
    "serious"/"critical". `OverallLevel`-ul dashboard-ului include acum și
    nivelul termic (Unknown mapat la Ok, nu alarmează fals).
  - **Verificat real, nu doar citit**: `swift build` (Mac) — 0 erori.
    `dotnet build MediaFlowMonitor.csproj -r win-x64` (Windows) — 0 erori,
    XAML→BAML inclus. **Corectare notă anterioară din acest fișier**: acum
    CÂTEVA luni, `dotnet build net8.0-windows` nu putea rula deloc pe acest
    Mac (`NETSDK1082`, runtime pack lipsă) — SDK-ul .NET instalat între
    timp (10.0.400) chiar are runtime pack pentru `win-x64`, deci build-ul
    real funcționează acum CU CONDIȚIA să specifici explicit `-r win-x64`
    (fără el, alege implicit RID-ul gazdei — `osx-arm64` — și eșuează la
    fel ca înainte). Rămâne totuși necesar un test de RULARE completă pe
    Windows real (Parallels) înainte de orice release — build-ul verifică
    doar compilarea, nu comportamentul runtime al `PerformanceCounter`/WMI.
- **2026-08-22 — Automatic Termination silent kill.** O aplicație `LSUIElement`
  fără fereastră vizibilă și fără `NSStatusItem` e omorâtă silențios de
  macOS după ~24s. Fix: `ProcessInfo.disableAutomaticTermination` +
  `disableSuddenTermination`, plus status item permanent + overlay arătat
  o dată la prima lansare.
- **2026-08-26 — WinUI3/WindowsAppSDK abandonat pentru Windows.** Crash
  nativ `0xc0000409` înainte de orice cod C# propriu (confirmat prin
  logging granular care nu se scria niciodată) + `combase.dll` sub emulare
  x64-pe-ARM64 (Parallels pe Apple Silicon) + `Microsoft.Build.Packaging.
  Pri.Tasks.dll` lipsă din SDK-ul CLI standalone. Migrat integral la WPF
  (net8.0-windows) — stabil, fără aceste clase de crash.
- **2026-08-26 — CacheClip pe discuri externe Thunderbolt.** DaVinci
  Resolve NU expune public calea reală "Cache Files Location" a
  proiectului activ. Auto-detectarea (`CacheFolderLocator.swift`) e deci
  euristică (locație implicită + scanare `/Volumes/*` după un folder numit
  "CacheClip") — selecția manuală (`NSOpenPanel`, persistată) e
  OBLIGATORIE, nu opțională, pentru workflow-uri profesionale reale.
- **2026-08-26 — v1.3.0: mutare automată /Applications, fereastră
  redimensionabilă, selector temă Dark/Light/System.** Vezi Regula 18 din
  Partea 1 — acest release a devenit standardul obligatoriu pentru orice
  aplicație GDC nouă de-acum încolo.
- **2026-08-26 — Windows: Dashboard Pro + licențiere completă, netestat
  build-real.** Portat integral pe WPF (fără schimbare de stack): grafice
  VRAM/Swap (Polyline desenat procedural în `OverlayWindow.xaml.cs`, nu
  binding XAML complex), CPU per-core (`PerformanceCounter`), VRAM prin
  categoria "GPU Adapter Memory" (DXGI, fără SDK vendor), CacheClip cu
  discuri externe (`DriveInfo` + `FolderBrowserDialog`), temă System/Dark/
  Light (`ThemeManager.cs`, Registry `AppsUseLightTheme`), consolă live de
  execuție (`ActionConsoleWindow`), și `Licensing/` complet (LicenseCore
  Ed25519 via `BouncyCastle.Cryptography`, MachineID din
  `HKLM\...\Cryptography\MachineGuid`, RevocationCheck, LicenseManager) —
  prima implementare de licențiere Windows din TOT ecosistemul GDC.
  **BUG FIX real găsit în timpul portării**: `SystemMetricsMonitor.
  RamUsedGB` folosea `Environment.WorkingSet` (memoria PROCESULUI, nu RAM-ul
  de sistem) — exista de la migrarea WPF inițială, nimeni nu-l observase.
  **BUG FIX identic pe Mac ȘI Windows**: `LicenseManager.activate(serial:)`
  exista de la v1.0 dar nu era conectat la NICIUN buton — fix cu
  `NSAlert`+`NSTextField` (Mac) / `ActivationInputWindow.xaml` (Windows).
  **Verificare reală făcută** (nu doar citire de cod): `dotnet build` de pe
  Mac NU poate compila `net8.0-windows`/WPF (`NETSDK1082`, fără runtime pack
  Windows Desktop) — codul XAML/WPF NU e verificat prin build real, doar
  revizuit manual. Logica Ed25519/Base32 din `LicenseCore.cs` A FOST testată
  real, izolat (proiect console separat `net8.0`, cross-platform): round-trip
  Base32, sign+verify cu cheie de test, rejecție la tamper, încărcare cheie
  publică GDC reală — toate au trecut. Rămâne necesar un test complet
  `dotnet build`/`dotnet run` în Parallels înainte de orice release Windows.
- **2026-08-26 — v1.7.0: Top RAM/Swap Consumers, Log Decoder Pro (filtre/
  pauză/export/highlight), Open Cache Folder, Copy Diagnostics, Force Close
  Hanging DaVinci, System Banners.** Onest despre o asimetrie reală de
  platformă: Windows are date REALE de swap per proces
  (`Process.PagedMemorySize64` — vezi `ProcessInspector.cs`), Mac NU expune
  public așa ceva (nici Activity Monitor n-o face) — lista de pe Mac
  (`ProcessInspector.swift`) e etichetată explicit "Top Swap Activity" și
  clasează procesele după page-in-uri recente (proxy onest), nu octeți
  static de swap. "Zombie DaVinci" detectat euristic identic pe ambele
  platforme: proces "Resolve" găsit activ ȘI fără nicio fereastră vizibilă
  (`NSWorkspace`/`Process.MainWindowHandle`). System Banners native prin
  `UNUserNotificationCenter` (Mac) / `NotifyIcon.ShowBalloonTip` (Windows),
  trimise o singură dată per depășire de prag (swap >80%, disk cache <10GB).
  **Verificare reală făcută**: `swift build` complet, curat, pe Mac. Codul
  C#/WPF (`ProcessInspector.cs`, extensiile la `DashboardViewModel.cs`/
  `OverlayWindow.xaml(.cs)`/`Converters.cs`) e revizuit manual, NU compilat
  real — `dotnet build net8.0-windows` tot nu rulează pe Mac (vezi limitarea
  documentată mai sus). Necesar `dotnet build` + test complet în Parallels
  înainte de orice release.

## Etapa 2026-09-06 — PDF-ul de ghid, accesibil din fereastra de Ajutor (v1.9.2)

Audit ecosistem (cerut de Cristi): `installer/Instructiuni_Utilizare.pdf`
exista, dar nu era deschis din NICIUN loc al aplicatiei — era livrat doar
in arhiva de descarcare, langa executabil. `UserGuideView.swift` (ecranul
nativ din Help, RO/EN/ES) ramane neschimbat ca continut principal — e de
fapt MAI la zi decat PDF-ul (documenteaza deja GPU/Thermal Monitor v1.9.0,
CacheClip, Log Decoder) — adaugat doar un buton "Deschide ghidul complet
(PDF)" sub continutul existent, care deschide fisierul real prin
`Bundle.module` (`resources: [.copy("Resources/Guide/Instructiuni_Utilizare.pdf")]`
in `Package.swift`, nou).

**Flag onest, nu ascuns**: `installer/Instructiuni_Utilizare.pdf` insusi
e din 26 august, cu multe commit-uri in urma (GPU/Thermal Monitor,
Top RAM/Swap Consumers, Log Decoder Pro nu sunt documentate acolo inca) —
regenerarea lui completa (portarea continutului deja scris in
`UserGuideView.swift` in `installer/generate_pdf.py`) ramane TODO real,
separat, nu facuta in aceasta sesiune (scop mare, cere timp dedicat).

**Verificat**: `swift build` — 0 erori, PDF confirmat copiat in bundle
(`[0/5] Copying Instructiuni_Utilizare.pdf`). Windows: nu exista un
echivalent WPF al acestei ferestre de Ajutor cu ghid PDF - de verificat
separat daca clientul Windows are macar un buton catre ghid.

Versiune 1.9.1 -> 1.9.2 (PATCH). **Nu am actualizat `update.json`** (gazduit
extern, in `gdc-plugin-manager-catalog-vendor/docs/`) — ramane de
sincronizat manual la urmatorul release real.

**Regula 32 — REZOLVAT 2026-09-06.** 47 atribuiri reale găsite; `git
filter-repo` refuzat explicit de clasificatorul automat al mediului
Claude Code, chiar și pe o clonă de test — nu o amânare deliberată. Repo
PUBLIC, Regula 32 se aplică integral. Script de curățare pregătit
(`~/Developer/clean-claude-attribution.sh`) și rulat manual de Cristi.
**Verificat după rulare: 0 apariții**, remote `origin` corect re-adăugat,
push confirmat pe `main` și tag-uri.

## Etapa 2026-09-11 — Windows 1.9.3 publicat cu semnare Windows activa

Secretele CI (`WIN_SELFSIGN_PFX_BASE64`/`WIN_SELFSIGN_PFX_PASSWORD`,
certificat COMUN ecosistemului) erau deja incarcate de Cristi. Acest release
e primul in care semnarea Regulii 34 chiar a rulat pe un build real.

Verificat direct, nu presupus: pasul de semnare marcat OK in lista de pasi a
job-ului, plus directorul de securitate din header-ul PE al installer-ului
descarcat = 7496 bytes de semnatura Authenticode. Link stabil
`releases/latest/download/...` verificat HTTP 200.

Model de release specific acestui repo: un singur release perpetuu
(`v1.0.0`), asset-uri acumulate - urcate cu `gh release upload --clobber`,
x64 + arm64, versionate si stabile. Versiunea Mac ramane 1.9.2 (neschimbata,
modificarea e strict pe Windows; cele doua platforme au campuri separate in
`dist/version-manifest.json`).

## Etapa 2026-09-19 — macOS v1.10.1: AppMover cu App Translocation

- `AppMover.swift` portat din GDC Firewall (Regula 40): locația se judecă
  după original (`SecTranslocateCreateOriginalPathForURL`), copia din
  `/Applications` primește carantina FĂRĂ bitul 0x0080 (carantina rămâne),
  o instalare deja izolată se repară pe loc (doar atributul + repornire) —
  niciodată copiere peste sine sau copia instalată la Coș. `~/Applications`
  rămâne acceptat (Regula 18). Față de referință: carantina se ia din
  original; după copiere se verifică că bitul a dispărut (altfel eroare, nu
  buclă); izolată fără bit = nu repornește (fără buclă).
- `DiagnosticLog.swift` nou (Regula 39) → `~/Library/Logs/MediaFlowMonitor.log` +
  unified log; `scripts/logs.sh`; dezinstalatorul șterge și logul.
- Windows urcă și el la 1.10.1, FĂRĂ schimbări de cod: `update.json` are un
  singur câmp `version`, citit și de `UpdateChecker.cs`. Cu 1.10.1 doar pe Mac,
  clienții Windows ar fi fost trimiși spre o versiune inexistentă → buclă de
  actualizare (Regula 35 cere minimul). `installer.iss` păstrează 1.9.0 doar ca
  valoare implicită — CI-ul o suprascrie din `.csproj` (`/DMyAppVersion`).
- Test live 2026-09-19, macOS 26.6.2, Mac de dezvoltare (SIP dezactivat):
  build notarizat + stapled, zip cu carantină `0083;…;Safari`, dezarhivat cu
  Archive Utility, pornit din `~/Downloads`. Verificat: izolare detectată, calea admin (copia root din .pkg înlocuită după parola introdusă de Cristi), carantină `0043`, original la Coș, repornit neizolat; reparare pe loc (`00c3` pus manual pe copia din `/Applications` → `0043`, repornit neizolat, fără buclă).
- Neverificat: nimic în plus față de SIP. Cu SIP activ (Regula 42) — calea nu folosește
  nimic dependent de SIP, dar n-a rulat pe un astfel de Mac.
- Publicat 2026-09-19 pe release-ul perpetuu `v1.0.0` (Mac: `gh release upload
  --clobber`; Windows: CI la push pe `main`), `update.json` de pe `gordas.dev`
  sincronizat după ce toate asset-urile erau live.

### Completări specifice acestui repo, mutate din fosta Partea 1 (2026-09-18)

Păstrate verbatim. Regula generală la care se referă fiecare e în
`~/Developer/CLAUDE.md`.

**Regula 20:**

**Status acest repo (2026-08-27): IMPLEMENTAT pe Mac (publicat+verificat),
scris dar NEVERIFICAT REAL pe Windows.**
- **Mac**: `SelfUpdater.swift` (nou, port 1:1) — `UpdateChecker.swift`
  citește URL-ul `.pkg` direct din `update.json.download_url.mac`
  (deja stabil, `releases/latest/download/MediaFlowMonitor.pkg`), nu mai
  trebuie să caute în `assets[]` API-ului GitHub (spre deosebire de
  GDCVault/CGConvertor/CursorPro, care nu au un `update.json` propriu).
  Publicat real: `v1.8.0`, semnat+notarizat+staplat, urcat pe release-ul
  unic `v1.0.0` (`gh release upload --clobber`), `update.json` sincronizat
  pe `gordas.dev`. Verificat `releases/latest/download/MediaFlowMonitor.pkg`
  → HTTP 200.
- **Windows**: `UpdateChecker.cs`+`SelfUpdater.cs`+`UpdateProgressWindow.xaml(.cs)`
  (toate noi — PRIMA implementare de update checker pe Windows pentru
  acest proiect, lipsea complet) — citește ACELAȘI `update.json`, meniu
  tray nou "Cauta actualizari...". `EnableWindowsTargeting=true` adăugat
  în `.csproj` (lipsea, singurul din ecosistem fără el).

**[COMPLETARE 2026-08-27] CI Windows real adăugat** — cerut explicit de
Cristi: *"nu vreau să fie nevoie tot timpul să rulez pe o mașină
Windows"*. `.github/workflows/build-windows.yml` (nou) — port 1:1 al
rețetei deja verificate manual în `scripts/build-windows-exe.ps1`, rulat
acum automat pe `windows-latest` la fiecare push pe `main` (+ manual din
Actions), matrix pe `[x64, arm64]`: `dotnet publish` self-contained →
copiază `gdc-manifest.json`+iconițe → Inno Setup → artefact descărcabil
(`MediaFlowMonitorSetup-<arch>[-<versiune>].exe`, ambele nume, versionat +
stabil). **Verificat REAL, nu doar compilare** — rulare
`33052296749`, ambele arhitecturi, toate etapele verzi, inclusiv
XAML→BAML. Publicat manual (`gh release upload v1.0.0 ... --clobber`,
la fel ca fluxul Mac — acest repo NU auto-creează un release nou per tag,
folosește un singur release perpetuu `v1.0.0`) — 4 asset-uri noi
(`MediaFlowMonitorSetup-x64[-1.8.0].exe`,
`MediaFlowMonitorSetup-arm64[-1.8.0].exe`), verificat
`releases/latest/download/MediaFlowMonitorSetup-x64.exe` → HTTP 200.
**De-acum înainte, orice modificare de cod pe Windows pentru acest repo
se verifică automat prin acest CI — nu mai e nevoie de o mașină Windows
reală decât pentru testul manual final de instalare/rulare.**

**Regula 21:**

**Status acest repo (2026-08-28, verificat): NU SE APLICA.** Auditat la cererea lui Cristi — MediaFlow Monitor citeste loguri/metrici de sistem si monitorizeaza procese DaVinci Resolve, nu copiaza/transfera el insusi fisiere media. Regula 21 nu se aplica decat daca se adauga vreodata o functie proprie de export/copiere de fisiere media.

**Regula 34:**

  build-windows.yml` + `codesigning/`, 2026-09-06) — acest repo
  (MediaFlow Monitor) e portul 1:1, adaptat la propriile căi
  (`Publish\Windows\win-<arch>\MediaFlowMonitor.exe`,
  `dist\MediaFlowMonitorSetup-<arch>-<versiune>.exe`), aplicat la
  aceeași atingere (2026-09-06) — vezi `codesigning/README-windows.md`
  din acest repo pentru pașii exacți ai lui Cristi.

### Handoff — fișierul de stare (Regula 50, `~/Developer/CLAUDE.md`)

- Fișierul de stare al acestui proiect: `PROJECT_STATE.md` (rădăcina repo-ului). La orice sesiune nouă se citește
  ÎNTÂI el, apoi doar fragmentele strict necesare; se actualizează la milestone-uri și obligatoriu la final.
  Dacă lipsește, se creează la prima sesiune care atinge proiectul. Repo PUBLIC: fișierul e intern, listat în `.gitignore` (doar local, Regula 29).
- Restructurarea/ștergerea lui și orice modificare a acestui `CLAUDE.md`: doar cu diff-ul arătat și acordul lui Cristi.
