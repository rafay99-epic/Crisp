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
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"
BINARY="$BIN_DIR/Crisp"
WATCHER="$BIN_DIR/CrispWatcher"
CLEANER="$BIN_DIR/CrispClean"
FILLER="$BIN_DIR/crisp-filler"
EMBED="$BIN_DIR/crisp-embed"

APP="build/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/Crisp"
# The background watch-folder agent — a second executable so it can run as a
# login-item LaunchAgent even when the main window is closed (see the LaunchAgent
# plist staged below).
cp "$WATCHER" "$APP/Contents/MacOS/CrispWatcher"
# The Finder Quick Action's cleaner — invoked by the installed Automator workflow.
cp "$CLEANER" "$APP/Contents/MacOS/CrispClean"
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
# The on-device filler detector (swift-built, not vendored). Lives beside
# whisper-cli in engine/bin so the engine-bin signing loop below covers it and
# CleanEngine.bundledTool("crisp-filler") finds it.
cp "$FILLER" "$APP/Contents/Resources/engine/bin/crisp-filler"
# The semantic-similarity helper for retake detection — same deal: beside the other
# engine binaries so the signing loop covers it and CleanEngine finds it (CRISP_EMBED).
cp "$EMBED" "$APP/Contents/Resources/engine/bin/crisp-embed"

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

# Watch-folder LaunchAgent. Staged into Contents/Library/LaunchAgents/ with a
# per-channel Label + AssociatedBundleIdentifiers so the three channels each get
# their own agent. SMAppService.agent(plistName:) registers it from the app.
mkdir -p "$APP/Contents/Library/LaunchAgents"
LAUNCH_AGENT="$APP/Contents/Library/LaunchAgents/$BUNDLE_ID.watcher.plist"
cp Resources/LaunchAgent.plist "$LAUNCH_AGENT"
"$PB" -c "Set :Label $BUNDLE_ID.watcher" "$LAUNCH_AGENT"
"$PB" -c "Set :AssociatedBundleIdentifiers:0 $BUNDLE_ID" "$LAUNCH_AGENT"
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

# App Intents metadata — Shortcuts/Spotlight read
# Contents/Resources/Metadata.appintents. `swift build` emits Crisp.swiftconstvalues
# (via the -emit-const-values flag wired into Package.swift);
# appintentsmetadataprocessor (ships in the Xcode toolchain) compiles it into the
# bundle. Needs Xcode — on a Command-Line-Tools-only machine it's skipped with a
# warning (the Finder Service still works; only the Shortcuts action is affected).
AIMP="$(xcrun --find appintentsmetadataprocessor 2>/dev/null || true)"
CONSTVALS="$BIN_DIR/Crisp.build/Crisp.swiftconstvalues"
if [[ -n "$AIMP" && -f "$CONSTVALS" ]]; then
  echo "Generating App Intents (Shortcuts) metadata…"
  TOOLCHAIN_DIR="$(dirname "$(dirname "$(dirname "$AIMP")")")"   # …/XcodeDefault.xctoolchain
  SRCL="$(mktemp)"; CVL="$(mktemp)"
  find Sources/Crisp -name '*.swift' > "$SRCL"
  echo "$CONSTVALS" > "$CVL"
  "$AIMP" \
    --output "$APP/Contents/Resources" \
    --toolchain-dir "$TOOLCHAIN_DIR" \
    --module-name Crisp \
    --sdk-root "$(xcrun --sdk macosx --show-sdk-path)" \
    --xcode-version "$(xcodebuild -version | awk '/Build version/{print $3}')" \
    --platform-family macOS \
    --deployment-target 15.0 \
    --target-triple arm64-apple-macos15.0 \
    --source-file-list "$SRCL" \
    --swift-const-vals-list "$CVL" \
    --force
  rm -f "$SRCL" "$CVL"
else
  echo "⚠️  appintentsmetadataprocessor/const-values unavailable — skipping Shortcuts metadata."
fi

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
# The watch-folder agent and Quick Action cleaner are additional Mach-Os in
# Contents/MacOS — sign them before the outer app seal (codesign won't sign
# sibling executables on its own).
codesign "${SIGN_OPTS[@]}" "$APP/Contents/MacOS/CrispWatcher"
codesign "${SIGN_OPTS[@]}" "$APP/Contents/MacOS/CrispClean"
codesign "${SIGN_OPTS[@]}" "$APP"
echo "Done → $PWD/$APP"
