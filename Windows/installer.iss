; Instalator Windows pentru MediaFlow Monitor, cu Inno Setup
; (https://jrsoftware.org/isinfo.php - gratuit). Port 1:1 al tiparului
; installer.iss din CGConvertor/GDCVaultWin/GDCPluginManagerWin, adaptat
; pentru un build `dotnet publish` self-contained (folder cu multe DLL-uri,
; nu un singur .exe PyInstaller onefile).
;
; Arhitectura se paseaza la compilare via /D (vezi scripts\build-windows-exe.ps1):
;   iscc /DMyAppArch=x64   installer.iss
;   iscc /DMyAppArch=arm64 installer.iss
; PublishDir trebuie sa contina deja outputul `dotnet publish` pentru acel Rid
; (Publish\Windows\win-x64 sau Publish\Windows\win-arm64).
;
; NU semnat cu certificat Authenticode - ecosistemul GDC nu are inca un
; certificat de code-signing Windows (spre deosebire de Apple Developer ID,
; deja configurat pentru Mac). Windows SmartScreen va arata un avertisment
; "Windows protected your PC" / "Unrecognized app" la prima rulare -
; identic cu restul aplicatiilor Windows din ecosistem (CGConvertor,
; GDCVaultWin) pana la achizitionarea unui certificat OV/EV.

#ifndef MyAppArch
  #define MyAppArch "x64"
#endif
#ifndef MyAppVersion
  #define MyAppVersion "1.7.0"
#endif

#define MyAppName "MediaFlow Monitor"
#define MyAppPublisher "GDC"
#define MyAppExeName "MediaFlowMonitor.exe"
#define MyAppURL "https://gordas.dev/media-flow-monitor"
#define PublishDir "..\Publish\Windows\win-" + MyAppArch

[Setup]
AppId={{A3F1D9E4-6B27-4C88-9A45-MEDIAFLOWMON01}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\GDC\MediaFlow Monitor
DefaultGroupName=MediaFlow Monitor
DisableProgramGroupPage=yes
OutputDir=..\dist
OutputBaseFilename=MediaFlowMonitorSetup-{#MyAppArch}-{#MyAppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
#if MyAppArch == "arm64"
ArchitecturesAllowed=arm64
ArchitecturesInstallIn64BitMode=arm64
#else
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
#endif
SetupIconFile=..\Resources\GDC\gdc-icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

; Recursiv - `dotnet publish` self-contained produce zeci de DLL-uri
; (runtime .NET inclus), nu doar executabilul.
[Files]
Source: "{#PublishDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Dezinstaleaza {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent

; REGULA PERMANENTA de Clean Uninstall (CLAUDE.md) - sterge folderul din
; Program Files (automat, Inno) + cheia de Registry scrisa de aplicatie
; (tema, cache path override, serial de licenta - vezi ThemeManager.cs,
; CacheFolderLocator.cs, LicenseManager.cs, toate sub aceeasi cheie).
[Registry]
Root: HKCU; Subkey: "Software\GDC\MediaFlowMonitor"; Flags: uninsdeletekey
