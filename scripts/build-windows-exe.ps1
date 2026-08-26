# Rulează ACEST script pe mașina Windows (PowerShell), din rădăcina repo-ului.
# Publică executabil standalone, self-contained, unpackaged (fără MSIX),
# unsigned — conform fazei curente de dezvoltare privată.

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Proj = Join-Path $Root "Windows\MediaFlowMonitor\MediaFlowMonitor.csproj"
$Out  = Join-Path $Root "Publish\Windows"

Write-Host "-> dotnet publish (Release, self-contained, win-x64)..."
# -p:Platform=x64 e OBLIGATORIU aici — fara el, csproj foloseste implicit
# AnyCPU, iar WindowsAppSDK.SelfContained.targets refuza sa publice
# self-contained pe AnyCPU (eroare: "The platform 'AnyCPU' is not
# supported for Self Contained mode"). -r win-x64 singur NU seteaza $(Platform).
dotnet publish $Proj `
  -c Release `
  -r win-x64 `
  -p:Platform=x64 `
  --self-contained true `
  -p:WindowsAppSDKSelfContained=true `
  -p:PublishSingleFile=false `
  -o $Out

if (-not (Test-Path $Out)) {
  Write-Error "Publish esuat — folderul $Out nu a fost creat. Vezi eroarea dotnet publish de mai sus."
  exit 1
}

Write-Host "-> Copiere manifest GDC + iconita in $Out..."
Copy-Item (Join-Path $Root "gdc-manifest.json") $Out -Force
$GdcOut = Join-Path $Out "Resources\GDC"
New-Item -ItemType Directory -Force -Path $GdcOut | Out-Null
Copy-Item (Join-Path $Root "Resources\GDC\gdc-icon.png") $GdcOut -Force
Copy-Item (Join-Path $Root "Resources\GDC\gdc-icon.ico") $GdcOut -Force

Write-Host "-> Impachetare arhiva privata de test (dist\)..."
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
Write-Host "Gata: $Out\MediaFlowMonitor.exe"
Write-Host "Manifest GDC: $Out\gdc-manifest.json"
Write-Host "Arhiva privata: $ZipPath (sha256: $Sha256)"
Write-Host "Ruleaza direct .exe-ul, apoi testeaza Ctrl+Shift+M."
