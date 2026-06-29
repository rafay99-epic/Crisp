#!/bin/zsh
# Builds the CURRENT branch as the Dev channel and installs it next to Stable.
# Stable (/Applications/Crisp.app) is never touched — break Dev all you like.
# Usage: ./dev.sh
set -euo pipefail
cd "$(dirname "$0")"

# Load Polar account identifiers (gitignored, not committed) so the Dev build's
# licensing endpoints are injected. Optional — if absent, licensing stays inert.
[ -f .polar.env ] && set -a && . ./.polar.env && set +a

CRISP_CHANNEL=dev ./build.sh

APP="build/Crisp Dev.app"
DEST="/Applications/Crisp Dev.app"

echo "Installing → $DEST"
osascript -e 'tell application "Crisp Dev" to quit' 2>/dev/null || true
sleep 1
rm -rf "$DEST"
ditto "$APP" "$DEST"
open "$DEST"
echo "Launched Crisp Dev — branch $(git rev-parse --abbrev-ref HEAD 2>/dev/null) @ $(git rev-parse --short HEAD 2>/dev/null)"
