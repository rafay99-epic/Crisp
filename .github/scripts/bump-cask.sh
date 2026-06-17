#!/usr/bin/env bash
#
# Bump the `crisp` Homebrew cask to a freshly published release.
#
# Called by ci.yml's release job right after `gh release create`, so the tap
# never goes stale and nobody hand-edits a sha256 again. The stable cask is
# version-pinned (Casks/crisp.rb), so each release needs version + sha256
# updated — this computes the sha256 of the DMG we just shipped and pushes that
# change straight to the tap's `main` (which isn't branch-protected).
#
# Usage:  VERSION=0.3 TAP_TOKEN=… bump-cask.sh /abs/path/Crisp.dmg
#
# Requires: git, shasum. TAP_TOKEN is a fine-grained PAT with Contents: Read &
# Write on rafay99-epic/homebrew-apps. Runs on a macOS runner (BSD sed).

set -euo pipefail

VERSION="${VERSION:?VERSION env var required}"
DMG="${1:?path to the Crisp.dmg required}"
: "${TAP_TOKEN:?TAP_TOKEN env var required}"

SHA=$(shasum -a 256 "$DMG" | awk '{print $1}')
echo "Bumping crisp cask → ${VERSION}  (${SHA})"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
git clone --depth 1 \
  "https://x-access-token:${TAP_TOKEN}@github.com/rafay99-epic/homebrew-apps.git" "$WORK"

CASK="$WORK/Casks/crisp.rb"
# Rewrite only the two pinned lines in the top stanza (anchored to a 2-space
# indent so livecheck/url/etc. are never touched).
sed -i '' -E \
  -e "s|^  version \"[^\"]*\"|  version \"${VERSION}\"|" \
  -e "s|^  sha256 \"[0-9a-f]*\"|  sha256 \"${SHA}\"|" \
  "$CASK"

cd "$WORK"
if git diff --quiet -- Casks/crisp.rb; then
  echo "::notice::crisp cask already at ${VERSION} — nothing to push."
  exit 0
fi

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git add Casks/crisp.rb
git commit -m "crisp ${VERSION}"
git push origin HEAD:main
echo "::notice::Pushed crisp ${VERSION} to the homebrew-apps tap."
