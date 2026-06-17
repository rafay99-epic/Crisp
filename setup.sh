#!/bin/bash
# One-time setup for building/running Crisp locally.
#   1. Installs the runtime tools (ffmpeg, whisper.cpp) via Homebrew.
#   2. Downloads the whisper speech model (148 MB, gitignored).
#   3. Checks the Swift toolchain (Xcode) needed to build the app.
# After this, build the app with:  cd apps/desktop && ./dev.sh
set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"
MODEL_DIR="$ROOT/apps/desktop/Resources/engine/models"
MODEL="$MODEL_DIR/ggml-base.en.bin"
MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin"

echo "=== Crisp — setup ==="

if ! command -v brew >/dev/null 2>&1; then
  echo "ERROR: Homebrew is required. Install it from https://brew.sh first."
  exit 1
fi

echo "→ Checking ffmpeg ..."
command -v ffmpeg >/dev/null 2>&1 || brew install ffmpeg

echo "→ Checking whisper.cpp ..."
command -v whisper-cli >/dev/null 2>&1 || command -v whisper-cpp >/dev/null 2>&1 || brew install whisper-cpp

echo "→ Checking cmake (builds the bundled whisper-cli in Scripts/vendor.sh) ..."
command -v cmake >/dev/null 2>&1 || brew install cmake

echo "→ Checking Swift toolchain ..."
if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo "ERROR: Xcode (with the macOS SDK) is required to build the app."
  echo "       Install Xcode from the App Store, then re-run setup."
  exit 1
fi

echo "→ Checking speech model ..."
if [ ! -f "$MODEL" ]; then
  mkdir -p "$MODEL_DIR"
  curl -L --fail -o "$MODEL" "$MODEL_URL"
fi

echo
echo "✅ Setup complete."
echo "   Build & run the Dev app:   cd apps/desktop && ./dev.sh"
