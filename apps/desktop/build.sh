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

# Preflight: if licensing is switched ON, the Polar config must be present, else
# we'd ship a paywalled build whose activation/checkout silently fails at runtime.
# Fail fast in CI instead of publishing a misconfigured artifact.
case "$(echo "${CRISP_LICENSING:-}" | tr '[:upper:]' '[:lower:]')" in
  1|yes|true)
    for var in CRISP_POLAR_ORG_ID CRISP_POLAR_CHECKOUT_URL CRISP_POLAR_PORTAL_URL CRISP_POLAR_LOOKUP_URL; do
      if [ -z "${${(P)var:-}//[[:space:]]/}" ]; then
        echo "CRISP_LICENSING is on but $var is empty — refusing to build a paywalled app with broken Polar config." >&2
        exit 1
      fi
    done
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
cp ../../packages/engine/clean_video.py "$APP/Contents/Resources/engine/clean_video.py"
cp -R ../../packages/engine/crisp "$APP/Contents/Resources/engine/crisp"
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
# Polar.sh licensing kill-switch. Ships OFF — the feature is dark until this is
# flipped to YES (CRISP_LICENSING=YES ./build.sh). Read at runtime by
# Channel.licensingEnabled; absent/NO ⇒ the app behaves as if licensing didn't exist.
"$PB" -c "Add :CrispLicensingEnabled string ${CRISP_LICENSING:-NO}" "$APP/Contents/Info.plist" 2>/dev/null \
  || "$PB" -c "Set :CrispLicensingEnabled ${CRISP_LICENSING:-NO}" "$APP/Contents/Info.plist"
# Polar account identifiers (org id + checkout/portal/lookup URLs) — injected from
# CRISP_POLAR_* env vars so they live in build secrets, not committed source (read by
# PolarConfig). Only written when set; absent ⇒ PolarConfig returns nil (fine while
# the feature ships dark). Source for dev: a gitignored apps/desktop/.polar.env that
# dev.sh/nightly.sh load; for release: GitHub Actions secrets.
set_plist() {  # key, value — write only if value is non-empty
  [ -z "$2" ] && return 0
  "$PB" -c "Add :$1 string $2" "$APP/Contents/Info.plist" 2>/dev/null \
    || "$PB" -c "Set :$1 $2" "$APP/Contents/Info.plist"
}
set_plist CrispPolarOrgID        "${CRISP_POLAR_ORG_ID:-}"
set_plist CrispPolarCheckoutURL  "${CRISP_POLAR_CHECKOUT_URL:-}"
set_plist CrispPolarPortalURL    "${CRISP_POLAR_PORTAL_URL:-}"
set_plist CrispPolarLookupURL    "${CRISP_POLAR_LOOKUP_URL:-}"

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

# macOS 26 layered icon: author an Icon Composer .icon document (dark-gradient
# background fill + transparent waveform glyph layer) and compile it with actool
# into Assets.car, so the Dock icon adopts the system light/dark/tinted icon
# appearances. Cached beside the .icns — delete the .car to force a re-render.
# Older macOS keeps using the hand-rendered .icns; without Xcode's actool the
# step is skipped and the app ships the flat icon exactly as before.
CAR_CACHE="${ICON_CACHE%.icns}.car"
if [ ! -f "$CAR_CACHE" ] && xcrun --find actool >/dev/null 2>&1; then
  echo "Compiling layered icon (Assets.car)…"
  GLYPH="/tmp/crisp_icon_${CHANNEL}_glyph.png"
  swift Scripts/MakeIcon.swift "$GLYPH" "$CHANNEL" glyph
  ICON_SRC="/tmp/Crisp-$CHANNEL-icon/AppIcon.icon"
  rm -rf "$ICON_SRC" && mkdir -p "$ICON_SRC/Assets"
  cp "$GLYPH" "$ICON_SRC/Assets/waveform.png"
  cat > "$ICON_SRC/icon.json" <<'JSON'
{
  "fill" : {
    "linear-gradient" : [ "srgb:0.165,0.165,0.180,1.000", "srgb:0.086,0.086,0.094,1.000" ]
  },
  "groups" : [
    {
      "layers" : [
        {
          "image-name" : "waveform.png",
          "name" : "waveform"
        }
      ],
      "shadow" : {
        "kind" : "neutral",
        "opacity" : 0.5
      },
      "translucency" : {
        "enabled" : true,
        "value" : 0.5
      }
    }
  ],
  "supported-platforms" : {
    "circles" : [ "watchOS" ],
    "squares" : "shared"
  }
}
JSON
  CAR_TMP="/tmp/Crisp-$CHANNEL-car"
  rm -rf "$CAR_TMP" && mkdir -p "$CAR_TMP"
  xcrun actool "$ICON_SRC" --compile "$CAR_TMP" --app-icon AppIcon \
    --platform macosx --minimum-deployment-target 15.0 \
    --output-partial-info-plist "$CAR_TMP/partial.plist" \
    --output-format human-readable-text --notices --warnings --errors
  cp "$CAR_TMP/Assets.car" "$CAR_CACHE"
fi
if [ -f "$CAR_CACHE" ]; then
  cp "$CAR_CACHE" "$APP/Contents/Resources/Assets.car"
  "$PB" -c "Add :CFBundleIconName string AppIcon" "$APP/Contents/Info.plist" 2>/dev/null \
    || "$PB" -c "Set :CFBundleIconName AppIcon" "$APP/Contents/Info.plist"
fi

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
