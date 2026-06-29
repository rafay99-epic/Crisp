#!/bin/zsh
# Builds the CURRENT branch as the Nightly channel and installs it next to
# Stable (and Dev). Stable (/Applications/Crisp.app) is never touched. Use this
# to smoke-test a Nightly build locally before pushing to the `nightly` branch.
# A local build has build number 0, so it'll offer to pull the published Nightly.
# Usage: ./nightly.sh
set -euo pipefail
cd "$(dirname "$0")"

# Load Polar account identifiers (gitignored, not committed) so the build's licensing
# endpoints are injected. Optional — if absent, licensing stays inert.
[ -f .polar.env ] && set -a && . ./.polar.env && set +a

CRISP_CHANNEL=nightly ./build.sh

APP="build/Crisp Nightly.app"
DEST="/Applications/Crisp Nightly.app"

echo "Installing → $DEST"
osascript -e 'tell application "Crisp Nightly" to quit' 2>/dev/null || true
sleep 1
rm -rf "$DEST"
ditto "$APP" "$DEST"
open "$DEST"
echo "Launched Crisp Nightly — branch $(git rev-parse --abbrev-ref HEAD 2>/dev/null) @ $(git rev-parse --short HEAD 2>/dev/null)"
