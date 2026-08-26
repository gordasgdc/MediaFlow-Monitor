# Run THIS script on the Windows machine (PowerShell), from the repo root.
# Publishes a standalone, self-contained, unpackaged executable (no MSIX),
# unsigned - matches the current private-dev phase.
#
# NOTE: kept ASCII-only on purpose (no diacritics/em-dash) - Windows
# PowerShell 5.1 can misparse non-ASCII comments in a non-UTF8-BOM file
# and throw confusing "string missing terminator" errors far from the
# real line.

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Proj = Join-Path $Root "Windows\MediaFlowMonitor\MediaFlowMonitor.csproj"
$Out  = Join-Path $Root "Publish\Windows"

Write-Host "-> dotnet publish (Release, self-contained, win-x64)..."
# -p:Platform=x64 is REQUIRED here - without it the csproj defaults to
# AnyCPU, and WindowsAppSDK.SelfContained.targets refuses to publish
# self-contained on AnyCPU ("The platform 'AnyCPU' is not supported for
# Self Contained mode"). -r win-x64 alone does NOT set $(Platform).
dotnet publish $Proj -c Release -r win-x64 -p:Platform=x64 --self-contained true -p:WindowsAppSDKSelfContained=true -p:PublishSingleFile=false -o $Out

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
$ZipName = "MediaFlowMonitor-Windows-$Version.zip"
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
Write-Host "Done: $Out\MediaFlowMonitor.exe"
Write-Host "GDC manifest: $Out\gdc-manifest.json"
Write-Host "Private archive: $ZipPath (sha256: $Sha256)"
Write-Host "Run the .exe directly, then test Ctrl+Shift+M."
