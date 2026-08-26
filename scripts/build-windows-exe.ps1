# Run THIS script on the Windows machine (PowerShell), from the repo root.
# Publishes a standalone, self-contained executable, then builds a signed-
# ready Inno Setup installer (unsigned - see NOTE below).
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File scripts\build-windows-exe.ps1              (defaults to x64)
#   powershell -ExecutionPolicy Bypass -File scripts\build-windows-exe.ps1 -Arch arm64  (Apple Silicon Mac + Parallels/UTM = ARM64 Windows)
#
# NOTE: kept ASCII-only on purpose (no diacritics/em-dash) - Windows
# PowerShell 5.1 can misparse non-ASCII comments in a non-UTF8-BOM file
# and throw confusing "string missing terminator" errors far from the
# real line.
#
# Installer NOT signed with an Authenticode certificate - the GDC
# ecosystem does not have a paid Windows code-signing cert yet (unlike
# Apple Developer ID, already configured for Mac). SmartScreen will show
# "Windows protected your PC" on first run of the installer - same as
# CGConvertor/GDCVaultWin until a cert is bought. If ISCC.exe (Inno Setup
# Compiler) is not found, the .exe/.zip are still produced, just no
# installer - install Inno Setup free from https://jrsoftware.org/isdl.php.

param(
    [ValidateSet("x64", "arm64")]
    [string]$Arch = "x64"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Proj = Join-Path $Root "Windows\MediaFlowMonitor\MediaFlowMonitor.csproj"
$Out  = Join-Path $Root "Publish\Windows\win-$Arch"
$Rid  = "win-$Arch"

Write-Host "-> dotnet publish (Release, self-contained, $Rid)..."
dotnet publish $Proj -c Release -r $Rid --self-contained true -p:PublishSingleFile=false -o $Out

if (-not (Test-Path $Out)) {
    Write-Error "Publish failed - $Out was not created. See the dotnet publish error above."
    exit 1
}

# Versiune citita din .csproj (<Version>), nu hardcodata - Regula 14.
$Version = (dotnet msbuild $Proj -getProperty:Version).Trim()
if ([string]::IsNullOrWhiteSpace($Version)) { $Version = "1.0.0" }
Write-Host "-> Version: $Version"

Write-Host "-> Copying GDC manifest + icon into $Out..."
Copy-Item (Join-Path $Root "gdc-manifest.json") $Out -Force
$GdcOut = Join-Path $Out "Resources\GDC"
New-Item -ItemType Directory -Force -Path $GdcOut | Out-Null
Copy-Item (Join-Path $Root "Resources\GDC\gdc-icon.png") $GdcOut -Force
Copy-Item (Join-Path $Root "Resources\GDC\gdc-icon.ico") $GdcOut -Force

Write-Host "-> Packaging private test archive (dist\)..."
$DistDir = Join-Path $Root "dist"
$ZipName = "MediaFlowMonitor-Windows-$Version-$Arch.zip"
New-Item -ItemType Directory -Force -Path $DistDir | Out-Null
$ZipPath = Join-Path $DistDir $ZipName
if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }
Compress-Archive -Path (Join-Path $Out "*") -DestinationPath $ZipPath

$Sha256 = (Get-FileHash -Path $ZipPath -Algorithm SHA256).Hash.ToLower()
$VersionManifestPath = Join-Path $DistDir "version-manifest.json"
$Vm = Get-Content $VersionManifestPath -Raw | ConvertFrom-Json
$Vm.platforms.windows.version = $Version
$Vm.platforms.windows.packageUrl = "dist/MediaFlowMonitorSetup-$Arch-$Version.exe"
$Vm.platforms.windows.sha256 = $Sha256
$Vm | ConvertTo-Json -Depth 10 | Set-Content $VersionManifestPath

Write-Host ""
Write-Host "Done: $Out\MediaFlowMonitor.exe ($Arch)"
Write-Host "Private archive: $ZipPath (sha256: $Sha256)"

# --- Installer nativ (Inno Setup) ---
# winget instaleaza Inno Setup per-user, sub %LocalAppData%\Programs pe
# multe masini (nu Program Files) - verificat live 2026-08-26.
# BUG FIX (2026-08-26): Get-Command intoarce un CommandInfo (are .Source),
# dar Get-Item intoarce un FileInfo (are .FullName, NU .Source) - amestecul
# celor doua tipuri in aceeasi variabila facea "& $Iscc.Source" sa fie null
# cand ISCC venea din calea de fallback, nu din PATH. Fix: normalizam
# mereu la un simplu string de cale.
$IsccPath = $null
$FromPath = Get-Command "iscc.exe" -ErrorAction SilentlyContinue
if ($FromPath) { $IsccPath = $FromPath.Source }
if (-not $IsccPath) {
    $CandidatePaths = @(
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
        "${env:ProgramFiles}\Inno Setup 6\ISCC.exe",
        "$env:LocalAppData\Programs\Inno Setup 6\ISCC.exe"
    )
    foreach ($p in $CandidatePaths) {
        if (Test-Path $p) { $IsccPath = $p; break }
    }
}
if (-not $IsccPath) {
    Write-Host ""
    Write-Host "SKIP: ISCC.exe (Inno Setup Compiler) not found."
    Write-Host "Install it free from https://jrsoftware.org/isdl.php, then re-run this script"
    Write-Host "to also produce dist\MediaFlowMonitorSetup-$Arch-$Version.exe"
    exit 0
}

Write-Host "-> Building installer (Inno Setup, $Arch)... [$IsccPath]"
$IssPath = Join-Path $Root "Windows\installer.iss"
& $IsccPath "/DMyAppArch=$Arch" "/DMyAppVersion=$Version" $IssPath
if ($LASTEXITCODE -ne 0) {
    Write-Error "Inno Setup compilation failed (exit code $LASTEXITCODE)."
    exit 1
}

$InstallerPath = Join-Path $DistDir "MediaFlowMonitorSetup-$Arch-$Version.exe"
if (Test-Path $InstallerPath) {
    $InstallerSha256 = (Get-FileHash -Path $InstallerPath -Algorithm SHA256).Hash.ToLower()
    Write-Host ""
    Write-Host "Done: $InstallerPath (sha256: $InstallerSha256)"
    Write-Host "NOT signed - SmartScreen will warn on first run until a code-signing cert is bought."
} else {
    Write-Error "Expected installer not found at $InstallerPath - check installer.iss OutputBaseFilename."
    exit 1
}
