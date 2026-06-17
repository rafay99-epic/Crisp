#!/bin/zsh
# Builds the app from scratch. Usage: ./build.sh
#   CRISP_CHANNEL=stable (default) → Crisp.app           com.syntaxlabtechnology.crisp
#   CRISP_CHANNEL=nightly          → "Crisp Nightly.app" com.syntaxlabtechnology.crisp.nightly
#   CRISP_CHANNEL=dev              → "Crisp Dev.app"      com.syntaxlabtechnology.crisp.dev
# The channels install side by side (different bundle id + name + data + icon).
# Stable + Nightly auto-update from GitHub releases; Dev never does. CI builds
# Stable (ci.yml, no env var); nightly.yml builds Nightly.
set -euo pipefail
cd "$(dirname "$0")"

CHANNEL="${CRISP_CHANNEL:-stable}"
case "$CHANNEL" in
  stable)
    APP_NAME="Crisp"
    BUNDLE_ID="com.syntaxlabtechnology.crisp"
    ICON_CACHE="Resources/AppIcon.icns"
    ;;
  nightly)
    APP_NAME="Crisp Nightly"
    BUNDLE_ID="com.syntaxlabtechnology.crisp.nightly"
    ICON_CACHE="Resources/AppIcon-Nightly.icns"
    ;;
  dev)
    APP_NAME="Crisp Dev"
    BUNDLE_ID="com.syntaxlabtechnology.crisp.dev"
    ICON_CACHE="Resources/AppIcon-Dev.icns"
    ;;
  *)
    echo "CRISP_CHANNEL must be 'stable', 'nightly', or 'dev' (got '$CHANNEL')" >&2
    exit 1
    ;;
esac

echo "Compiling (arm64)…  [channel: $CHANNEL]"
# Apple Silicon only — Intel Macs are no longer supported, so we build a single
# arm64 slice (the bundled engine binaries are arm64 too).
swift build -c release --arch arm64
BINARY="$(swift build -c release --arch arm64 --show-bin-path)/Crisp"

APP="build/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/Crisp"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Bundle the cleaning engine so a downloaded DMG is self-contained: the Python
# script plus the binaries it drives (ffmpeg/ffprobe/whisper-cli/python). They're
# arm64 (Apple Silicon only), vendored (downloaded + whisper built from source)
# into .vendor/bin by Scripts/vendor.sh, then signed with the app below.
# The whisper *model* is NOT bundled — it's ~148 MB and would re-ship on every
# update, so the app downloads it once on first run into the channel's data dir.
echo "Vendoring engine binaries…"
./Scripts/vendor.sh
echo "Bundling cleaning engine…"
mkdir -p "$APP/Contents/Resources/engine"
cp Resources/engine/clean_video.py "$APP/Contents/Resources/engine/clean_video.py"
cp -R Resources/engine/crisp "$APP/Contents/Resources/engine/crisp"
find "$APP/Contents/Resources/engine/crisp" -name __pycache__ -type d -prune -exec rm -rf {} +
cp -R .vendor/bin "$APP/Contents/Resources/engine/bin"

PB=/usr/libexec/PlistBuddy
# Version is 0.<total commit count> — 10 commits → 0.10. CI passes
# CRISP_VERSION; local builds compute it from the repo. Nightly and Dev append
# a channel suffix (-nightly / -dev) and stamp the exact branch@sha so the About
# screen shows what's running. Stable ships a clean numeric version.
COMMIT_COUNT=$(git rev-list --count HEAD 2>/dev/null || echo 0)
VERSION="${CRISP_VERSION:-0.$COMMIT_COUNT}"
if [[ "$CHANNEL" != "stable" ]]; then
  BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
  SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "?")
  VERSION="$VERSION-$CHANNEL"
  "$PB" -c "Add :CrispBuildInfo string $BRANCH@$SHA" "$APP/Contents/Info.plist" 2>/dev/null \
    || "$PB" -c "Set :CrispBuildInfo $BRANCH@$SHA" "$APP/Contents/Info.plist"
fi
"$PB" -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
"$PB" -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"
"$PB" -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Contents/Info.plist"
"$PB" -c "Set :CFBundleName $APP_NAME" "$APP/Contents/Info.plist"
"$PB" -c "Add :CFBundleDisplayName string $APP_NAME" "$APP/Contents/Info.plist" 2>/dev/null \
  || "$PB" -c "Set :CFBundleDisplayName $APP_NAME" "$APP/Contents/Info.plist"
"$PB" -c "Set :CrispChannel $CHANNEL" "$APP/Contents/Info.plist"
# Monotonic build number (CI run number) — orders Nightly pre-releases for the
# updater. Absent/0 for local builds.
if [ -n "${CRISP_BUILD:-}" ]; then
  "$PB" -c "Add :CrispBuildNumber string $CRISP_BUILD" "$APP/Contents/Info.plist" 2>/dev/null \
    || "$PB" -c "Set :CrispBuildNumber $CRISP_BUILD" "$APP/Contents/Info.plist"
fi
echo "Version $VERSION  ($APP_NAME · $BUNDLE_ID)"

# Generate the channel's icon once; delete the cache file to force a re-render.
if [ ! -f "$ICON_CACHE" ]; then
  echo "Rendering $CHANNEL icon…"
  PNG="/tmp/crisp_icon_${CHANNEL}_1024.png"
  swift Scripts/MakeIcon.swift "$PNG" "$CHANNEL"
  ICONSET="/tmp/Crisp-$CHANNEL.iconset"
  rm -rf "$ICONSET" && mkdir "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$PNG" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    d=$((s * 2))
    sips -z $d $d "$PNG" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$ICON_CACHE"
fi
cp "$ICON_CACHE" "$APP/Contents/Resources/AppIcon.icns"

# Sign inside-out: every bundled Mach-O first, then the app. Defaults to ad-hoc
# (`-`); set CODESIGN_IDENTITY to a Developer ID to add hardened runtime +
# timestamp for notarization (the bundled binaries need the runtime too).
SIGN_ID="${CODESIGN_IDENTITY:--}"
SIGN_OPTS=(--force --sign "$SIGN_ID")
[[ "$SIGN_ID" != "-" ]] && SIGN_OPTS+=(--options runtime --timestamp)

echo "Signing bundled binaries…"
find "$APP/Contents/Resources/engine/bin" -type f -print0 | while IFS= read -r -d '' f; do
  if file "$f" | grep -q "Mach-O"; then
    codesign "${SIGN_OPTS[@]}" "$f" 2>/dev/null || true
  fi
done
codesign "${SIGN_OPTS[@]}" "$APP"
echo "Done → $PWD/$APP"
