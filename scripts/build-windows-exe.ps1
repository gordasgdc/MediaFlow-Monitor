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

# KNOWN ISSUE (real, hit and fixed 2026-08-26): building this WinUI3
# project with the standalone `dotnet` CLI fails with:
#   MSB4062: The "Microsoft.Build.Packaging.Pri.Tasks.ExpandPriContent"
#   task could not be loaded from ...\dotnet\sdk\<ver>\Microsoft\
#   VisualStudio\v<ver>\AppxPackage\Microsoft.Build.Packaging.Pri.Tasks.dll
# That DLL ships ONLY with Visual Studio's "WinUI application development"
# workload, at a DIFFERENT path (...\Microsoft Visual Studio\<ver>\
# Community\MSBuild\...\AppxPackage\), and the dotnet SDK's own targets
# expect it colocated with the SDK. Fix (one-time, Admin PowerShell):
#   $src = "C:\Program Files\Microsoft Visual Studio\<VS-ver>\Community\MSBuild\Microsoft\VisualStudio\v<VS-ver>.0\AppxPackage"
#   $dst = "C:\Program Files\dotnet\sdk\<SDK-ver>\Microsoft\VisualStudio\v<VS-ver>.0\AppxPackage"
#   New-Item -ItemType Directory -Force -Path $dst | Out-Null
#   Copy-Item "$src\*" $dst -Recurse -Force
# (adjust <VS-ver>/<SDK-ver> to what `dotnet --version` / VS Installer show)
$PriTaskProbe = Get-ChildItem -Path "C:\Program Files\dotnet\sdk" -Filter "Microsoft.Build.Packaging.Pri.Tasks.dll" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $PriTaskProbe) {
    Write-Warning "Microsoft.Build.Packaging.Pri.Tasks.dll not found under the dotnet SDK folder - the build below will likely fail with MSB4062. See the comment block above this line for the one-time Admin PowerShell fix."
}

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
