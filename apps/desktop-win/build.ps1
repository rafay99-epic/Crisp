<#
.SYNOPSIS
  Builds Crisp for Windows in any channel — the counterpart of the macOS build.sh.

.DESCRIPTION
  One script for all three channels (dev / nightly / stable), which install side by
  side because their identity + data home differ (~/.crisp, ~/.crisp-nightly,
  ~/.crisp-dev). Identity (channel / version / build number) is baked into the
  assembly with -p:CrispChannel/CrispVersion/CrispBuildNumber so an installed app
  knows what it is without an env var (env still overrides at runtime — see
  Common/BuildInfo.cs). Mirrors the CI publish step in .github/workflows/windows.yml.

    stable  -> Crisp        , updates from the latest GitHub release
    nightly -> Crisp Nightly, updates from the newest pre-release
    dev     -> Crisp Dev    , whatever you built locally, no updater

  Version is 0.<total commit count> (like the macOS build); CRISP_VERSION overrides.

.PARAMETER Channel
  dev (default) | nightly | stable.

.PARAMETER Configuration
  Release (default) | Debug.

.PARAMETER Vendor
  Also vendor the engine binaries (ffmpeg/ffprobe/whisper-cli/python) via
  Scripts/vendor-win.ps1 and bundle them, so cleaning actually runs. Heavy the first
  time (downloads + builds whisper-cli from source — needs CMake + VS Build Tools).
  Without it you still get the full UI; a clean stops at "ffprobe not found".

.PARAMETER Installer
  Build the self-contained Crisp-Setup.exe installer with Inno Setup (ISCC). Installs
  Inno Setup via winget/choco if missing.

.PARAMETER Install
  Copy the build into %LOCALAPPDATA%\Programs\<name> and make a Start-menu shortcut —
  the no-installer way to run a channel side by side (what dev.ps1 / nightly.ps1 use).

.PARAMETER Run
  Launch the app when done.

.PARAMETER Clean
  Remove this channel's publish output first.

.EXAMPLE
  .\build.ps1 -Channel dev -Install -Run      # build + install + launch "Crisp Dev"
  .\build.ps1 -Channel stable -Vendor -Installer   # full release-style installer
#>
[CmdletBinding()]
param(
    [ValidateSet('dev', 'nightly', 'stable')]
    [string]$Channel = 'dev',
    [ValidateSet('Release', 'Debug')]
    [string]$Configuration = 'Release',
    [switch]$Vendor,
    [switch]$Installer,
    [switch]$Install,
    [switch]$Run,
    [switch]$Clean,
    [string]$Version
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot   # → apps/desktop-win

# --- Channel identity (mirrors Common/Channel.cs) --------------------------------
$displayName = switch ($Channel) {
    'nightly' { 'Crisp Nightly' }
    'dev'     { 'Crisp Dev' }
    default   { 'Crisp' }
}
$assetName = switch ($Channel) {
    'nightly' { 'Crisp-Nightly-Setup.exe' }
    default   { 'Crisp-Setup.exe' }   # dev never ships an installer, but -Installer still works locally
}
$appIcon = switch ($Channel) {
    'nightly' { 'Assets\AppIcon-Nightly.ico' }
    'dev'     { 'Assets\AppIcon-Dev.ico' }
    default   { 'Assets\AppIcon.ico' }
}

# --- Version = 0.<commit count>; build number = same count (nightly orders on it) --
$commitCount = (git rev-list --count HEAD 2>$null); if (-not $commitCount) { $commitCount = '0' }
if (-not $Version) { $Version = if ($env:CRISP_VERSION) { $env:CRISP_VERSION } else { "0.$commitCount" } }
$buildNumber = if ($Channel -eq 'nightly') { $commitCount } else { '0' }
$branch = (git rev-parse --abbrev-ref HEAD 2>$null); $sha = (git rev-parse --short HEAD 2>$null)

Write-Host "Building $displayName  (channel: $Channel · v$Version · $branch@$sha)" -ForegroundColor Cyan

$publishDir = Join-Path $PSScriptRoot "publish\$Channel"
if ($Clean -and (Test-Path $publishDir)) { Remove-Item -Recurse -Force $publishDir }

# --- Optional: vendor the engine binaries ----------------------------------------
if ($Vendor) {
    Write-Host "Vendoring engine binaries (ffmpeg/whisper/python)…" -ForegroundColor Cyan
    & (Join-Path $PSScriptRoot 'Scripts\vendor-win.ps1')
    if ($LASTEXITCODE) { throw "vendor-win.ps1 failed ($LASTEXITCODE)" }
}

# --- Publish the self-contained app, baking in the channel identity --------------
Write-Host "Publishing self-contained win-x64…" -ForegroundColor Cyan
dotnet publish Crisp.csproj -c $Configuration -r win-x64 --self-contained `
    -p:CrispChannel=$Channel -p:CrispVersion=$Version -p:CrispBuildNumber=$buildNumber `
    -p:ApplicationIcon=$appIcon -o $publishDir
if ($LASTEXITCODE) { throw "dotnet publish failed ($LASTEXITCODE)" }

# --- Bundle the cleaning engine (shared with macOS) beside the exe ----------------
# The Python engine (clean_video.py + the crisp/ package) lives in packages/engine
# (shared by both apps); the app resolves it relative to the exe. Copy it, plus any
# vendored binaries, exactly like the CI packaging step.
Write-Host "Bundling cleaning engine…" -ForegroundColor Cyan
$engineSrc = Resolve-Path (Join-Path $PSScriptRoot '..\..\packages\engine')
$engineDst = Join-Path $publishDir 'engine'
if (Test-Path $engineDst) { Remove-Item -Recurse -Force $engineDst }
New-Item -ItemType Directory -Force -Path $engineDst | Out-Null
Copy-Item (Join-Path $engineSrc 'clean_video.py') $engineDst -Force
Copy-Item (Join-Path $engineSrc 'crisp') $engineDst -Recurse -Force
Get-ChildItem $engineDst -Recurse -Directory -Filter '__pycache__' | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

$vendorBin = Join-Path $PSScriptRoot '.vendor\bin'
if (Test-Path $vendorBin) {
    New-Item -ItemType Directory -Force -Path (Join-Path $engineDst 'bin') | Out-Null
    Copy-Item (Join-Path $vendorBin '*') (Join-Path $engineDst 'bin') -Recurse -Force
    Write-Host "  bundled vendored binaries from .vendor\bin"
}
elseif (-not $Vendor) {
    Write-Host "  (no engine binaries — pass -Vendor to bundle ffmpeg/whisper/python; a clean will otherwise report 'ffprobe not found')" -ForegroundColor DarkYellow
}

# --- Optional: build the Inno Setup installer ------------------------------------
if ($Installer) {
    $iscc = 'C:\Program Files (x86)\Inno Setup 6\ISCC.exe'
    if (-not (Test-Path $iscc)) {
        Write-Host "Installing Inno Setup…" -ForegroundColor Cyan
        if (Get-Command winget -ErrorAction SilentlyContinue) { winget install -e --id JRSoftware.InnoSetup --accept-source-agreements --accept-package-agreements }
        elseif (Get-Command choco -ErrorAction SilentlyContinue) { choco install innosetup -y --no-progress }
        else { throw "Inno Setup not found and neither winget nor choco is available to install it." }
    }
    Write-Host "Building installer…" -ForegroundColor Cyan
    & $iscc "/DSourceDir=$publishDir" "/DAppVersion=$Version" (Join-Path $PSScriptRoot 'Scripts\crisp.iss')
    if ($LASTEXITCODE) { throw "ISCC failed ($LASTEXITCODE)" }
    Move-Item (Join-Path $PSScriptRoot 'Scripts\Crisp-Setup.exe') (Join-Path $PSScriptRoot "Scripts\$assetName") -Force
    Write-Host "Installer → apps/desktop-win/Scripts/$assetName" -ForegroundColor Green
}

# --- Optional: install side by side (no installer) + Start-menu shortcut ----------
$launchExe = Join-Path $publishDir 'Crisp.exe'
if ($Install) {
    $installDir = Join-Path $env:LOCALAPPDATA "Programs\$displayName"
    Write-Host "Installing → $installDir" -ForegroundColor Cyan
    # Quit a running instance of THIS channel (matched by its install path) so the copy
    # can overwrite; other channels + a Stable install are left running.
    Get-Process -Name 'Crisp' -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -and $_.Path.StartsWith($installDir, [System.StringComparison]::OrdinalIgnoreCase) } |
        Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
    if (Test-Path $installDir) { Remove-Item -Recurse -Force $installDir }
    New-Item -ItemType Directory -Force -Path $installDir | Out-Null
    Copy-Item (Join-Path $publishDir '*') $installDir -Recurse -Force
    $launchExe = Join-Path $installDir 'Crisp.exe'

    $startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
    $lnk = Join-Path $startMenu "$displayName.lnk"
    $ws = New-Object -ComObject WScript.Shell
    $sc = $ws.CreateShortcut($lnk)
    $sc.TargetPath = $launchExe
    $sc.WorkingDirectory = $installDir
    $sc.Description = $displayName
    $sc.Save()
    Write-Host "Start-menu shortcut → $displayName" -ForegroundColor Green
}

Write-Host "Done → $displayName  v$Version  ($launchExe)" -ForegroundColor Green

if ($Run) {
    Write-Host "Launching $displayName…" -ForegroundColor Cyan
    Start-Process -FilePath $launchExe
}
