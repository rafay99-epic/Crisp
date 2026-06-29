# One-time setup for building/running Crisp locally on Windows.
#   1. Installs the runtime tools (ffmpeg, whisper.cpp) if missing.
#   2. Downloads the whisper speech model.
#   3. Checks the Swift toolchain needed to build the app on Windows.
$ErrorActionPreference = "Stop"

$ROOT = $PSScriptRoot
$MODEL_DIR = "$ROOT\apps\desktop\Resources\engine\models"
$MODEL = "$MODEL_DIR\ggml-base.en.bin"
$MODEL_URL = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin"

Write-Host "=== Crisp — setup ==="

Write-Host "→ Checking ffmpeg ..."
if (!(Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    Write-Host "ffmpeg not found. Installing via winget..."
    winget install --id=Gyan.FFmpeg -e --accept-source-agreements --accept-package-agreements
    Write-Host "ffmpeg installed. Please restart your terminal after this script finishes."
} else {
    Write-Host "ffmpeg is already installed."
}

Write-Host "→ Checking whisper.cpp ..."
$whisperFound = $false
foreach ($cmd in @("whisper-cli.exe", "whisper-cpp.exe", "main.exe")) {
    if (Get-Command $cmd -ErrorAction SilentlyContinue) {
        $whisperFound = $true
        break
    }
}
if (!$whisperFound) {
    Write-Host "WARNING: whisper-cli.exe not found in PATH."
    Write-Host "Please download whisper.cpp for Windows and add it to your PATH."
}

Write-Host "→ Checking cmake ..."
if (!(Get-Command cmake -ErrorAction SilentlyContinue)) {
    Write-Host "cmake not found. You can install it via: winget install CMake"
}

Write-Host "→ Checking Swift toolchain ..."
if (!(Get-Command swiftc -ErrorAction SilentlyContinue)) {
    Write-Host "WARNING: Swift toolchain not found."
    Write-Host "To build Crisp on Windows, you need the Swift Nightly toolchain installed."
}

Write-Host "→ Checking speech model ..."
if (!(Test-Path $MODEL)) {
    Write-Host "Downloading speech model (this might take a while)..."
    New-Item -ItemType Directory -Force -Path $MODEL_DIR | Out-Null
    Invoke-WebRequest -Uri $MODEL_URL -OutFile $MODEL
    Write-Host "Model downloaded successfully."
} else {
    Write-Host "Speech model already exists."
}

Write-Host ""
Write-Host "✅ Setup complete."
Write-Host "   Note: Since you are on Windows, building the app requires experimental Swift Windows support."
