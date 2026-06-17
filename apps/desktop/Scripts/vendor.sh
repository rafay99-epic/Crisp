#!/bin/zsh
# vendor.sh — fetch the engine binaries Crisp ships, into apps/desktop/.vendor/bin.
#
# Crisp drives ffmpeg / ffprobe / whisper-cli / python as subprocesses. To make a
# downloaded DMG self-contained (no Homebrew required), build.sh bundles these
# into the app and signs them alongside it. This script produces that binary tree.
#
# Everything is PINNED + hash-checked. ffmpeg/ffprobe/python are downloaded;
# whisper-cli is built from a pinned whisper.cpp tag (no official macOS CLI binary
# is published) — that needs cmake (`brew install cmake`; CI runners ship it).
#
# Apple-Silicon only by design — see CLAUDE.md / build.sh. Re-running is cheap:
# anything already staged in .vendor/bin is left alone. Pass --clean to rebuild.
set -euo pipefail
cd "$(dirname "$0")/.."          # → apps/desktop

VENDOR="$PWD/.vendor"
DL="$VENDOR/dl"
BIN="$VENDOR/bin"

[[ "${1:-}" == "--clean" ]] && rm -rf "$VENDOR"
mkdir -p "$DL" "$BIN"

# ---- Pinned sources -------------------------------------------------------
FFMPEG_URL="https://ffmpeg.martin-riedl.de/download/macos/arm64/1778761665_8.1.1/ffmpeg.zip"
FFMPEG_SHA="a05b1a47bb3ac89a95a55eec713f8bbb347051bb07015f3b7d08fb62ed81a21e"
FFPROBE_URL="https://ffmpeg.martin-riedl.de/download/macos/arm64/1778761665_8.1.1/ffprobe.zip"
FFPROBE_SHA="135e70d2518beeb568183952dbc4bdeca1628dd49a7376d57e6b27dbc57d209f"
PY_URL="https://github.com/astral-sh/python-build-standalone/releases/download/20260610/cpython-3.13.14+20260610-aarch64-apple-darwin-install_only_stripped.tar.gz"
PY_SHA="79daa8e9dea1e64ad50aebb05a807289023a474c2020b72361eb44d67fa2401e"
WHISPER_TAG="v1.9.0"

verify() {  # file expected-sha
  local got; got=$(shasum -a 256 "$1" | awk '{print $1}')
  if [[ "$got" != "$2" ]]; then
    echo "✗ checksum mismatch: $1" >&2
    echo "    expected $2" >&2
    echo "    got      $got" >&2
    exit 1
  fi
}

fetch() {  # url out-file expected-sha
  [[ -f "$2" ]] || { echo "  ↓ $(basename "$2")"; curl -sSL --fail -o "$2" "$1"; }
  verify "$2" "$3"
}

# ---- ffmpeg + ffprobe -----------------------------------------------------
if [[ ! -x "$BIN/ffmpeg" ]]; then
  fetch "$FFMPEG_URL" "$DL/ffmpeg.zip" "$FFMPEG_SHA"
  ditto -x -k "$DL/ffmpeg.zip" "$DL/ffmpeg_x" && cp "$DL/ffmpeg_x/ffmpeg" "$BIN/ffmpeg"
  chmod +x "$BIN/ffmpeg"
fi
if [[ ! -x "$BIN/ffprobe" ]]; then
  fetch "$FFPROBE_URL" "$DL/ffprobe.zip" "$FFPROBE_SHA"
  ditto -x -k "$DL/ffprobe.zip" "$DL/ffprobe_x" && cp "$DL/ffprobe_x/ffprobe" "$BIN/ffprobe"
  chmod +x "$BIN/ffprobe"
fi

# ---- python (stdlib-only runtime) -----------------------------------------
if [[ ! -x "$BIN/python/bin/python3" ]]; then
  fetch "$PY_URL" "$DL/python.tar.gz" "$PY_SHA"
  rm -rf "$DL/python" "$BIN/python"
  tar xzf "$DL/python.tar.gz" -C "$DL"        # → $DL/python
  # Trim what a stdlib-only engine never touches (pip/idle/tk/tests/docs).
  PYLIB="$DL/python/lib/python3.13"
  rm -rf "$PYLIB/test" "$PYLIB/idlelib" "$PYLIB/turtledemo" "$PYLIB/tkinter" \
         "$PYLIB/ensurepip" "$PYLIB/lib2to3" "$DL/python/share"
  rm -f "$DL"/python/bin/pip*(N) "$DL"/python/bin/idle*(N) "$DL"/python/bin/2to3*(N)
  mv "$DL/python" "$BIN/python"
fi

# ---- whisper-cli (built from a pinned tag) --------------------------------
if [[ ! -x "$BIN/whisper-cli" ]]; then
  command -v cmake >/dev/null 2>&1 || {
    echo "✗ cmake is required to build whisper-cli — install it with: brew install cmake" >&2
    exit 1
  }
  SRC="$DL/whisper.cpp"
  [[ -d "$SRC" ]] || git clone --depth 1 --branch "$WHISPER_TAG" \
    https://github.com/ggml-org/whisper.cpp "$SRC"
  cmake -S "$SRC" -B "$SRC/build" -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES=arm64 -DBUILD_SHARED_LIBS=OFF \
    -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_EXAMPLES=ON -DWHISPER_BUILD_SERVER=OFF \
    -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON
  cmake --build "$SRC/build" --config Release --target whisper-cli -j"$(sysctl -n hw.ncpu)"
  cp "$SRC/build/bin/whisper-cli" "$BIN/whisper-cli"
  chmod +x "$BIN/whisper-cli"
fi

echo "✅ Vendored engine binaries → $BIN"
du -sh "$BIN"/* 2>/dev/null || true
