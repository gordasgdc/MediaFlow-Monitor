# Run THIS script on the Windows machine (PowerShell), from the repo root.
# Publishes a standalone, self-contained, unpackaged executable (no MSIX),
# unsigned - matches the current private-dev phase.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File scripts\build-windows-exe.ps1              (defaults to x64)
#   powershell -ExecutionPolicy Bypass -File scripts\build-windows-exe.ps1 -Arch arm64  (Apple Silicon Mac + Parallels/UTM = ARM64 Windows)
#
# NOTE: kept ASCII-only on purpose (no diacritics/em-dash) - Windows
# PowerShell 5.1 can misparse non-ASCII comments in a non-UTF8-BOM file
# and throw confusing "string missing terminator" errors far from the
# real line.

param(
    [ValidateSet("x64", "arm64")]
    [string]$Arch = "x64"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Proj = Join-Path $Root "Windows\MediaFlowMonitor\MediaFlowMonitor.csproj"
$Out  = Join-Path $Root "Publish\Windows"
$Rid  = "win-$Arch"

# SWITCHED TO WPF (2026-08-26): WinUI3/WindowsAppSDK caused a chain of
# unfixable native crashes (PRI DLL missing from dotnet SDK, then
# 0xc000027b in combase.dll under x64-on-ARM64 emulation, then 0xc0000409
# crashing before ANY of our C# code ran - even on native ARM64). Switched
# the Windows UI to plain WPF, which has none of these MSIX/PRI/WinRT
# bootstrap dependencies and builds/runs with a plain `dotnet publish`.
# On an Apple Silicon Mac + Parallels, the VM is ARM64 Windows - use
# -Arch arm64 for a native build (x64 also works via emulation with WPF,
# since WPF has no WinRT bootstrap to trip over).
Write-Host "-> dotnet publish (Release, self-contained, $Rid)..."
dotnet publish $Proj -c Release -r $Rid --self-contained true -p:PublishSingleFile=false -o $Out

if (-not (Test-Path $Out)) {
    Write-Error "Publish failed - $Out was not created. See the dotnet publish error above."
    exit 1
}

Write-Host "-> Copying GDC manifest + icon into $Out..."
Copy-Item (Join-Path $Root "gdc-manifest.json") $Out -Force
$GdcOut = Join-Path $Out "Resources\GDC"
New-Item -ItemType Directory -Force -Path $GdcOut | Out-Null
Copy-Item (Join-Path $Root "Resources\GDC\gdc-icon.png") $GdcOut -Force
Copy-Item (Join-Path $Root "Resources\GDC\gdc-icon.ico") $GdcOut -Force

Write-Host "-> Packaging private test archive (dist\)..."
$Version = "1.0.0"
$DistDir = Join-Path $Root "dist"
$ZipName = "MediaFlowMonitor-Windows-$Version-$Arch.zip"
New-Item -ItemType Directory -Force -Path $DistDir | Out-Null
$ZipPath = Join-Path $DistDir $ZipName
if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }
Compress-Archive -Path (Join-Path $Out "*") -DestinationPath $ZipPath

$Sha256 = (Get-FileHash -Path $ZipPath -Algorithm SHA256).Hash.ToLower()
$VersionManifestPath = Join-Path $DistDir "version-manifest.json"
$Vm = Get-Content $VersionManifestPath -Raw | ConvertFrom-Json
$Vm.platforms.windows.sha256 = $Sha256
$Vm | ConvertTo-Json -Depth 10 | Set-Content $VersionManifestPath

Write-Host ""
Write-Host "Done: $Out\MediaFlowMonitor.exe ($Arch)"
Write-Host "GDC manifest: $Out\gdc-manifest.json"
Write-Host "Private archive: $ZipPath (sha256: $Sha256)"
Write-Host "Run the .exe directly, then test Ctrl+Shift+M."
