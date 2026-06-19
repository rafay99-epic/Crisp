#!/usr/bin/env bash
#
# highlights.sh <git-range>
#
# Emit a user-facing "## Highlights" Markdown section for the PRs in <git-range>,
# written by GitHub Models (free, native to Actions — no extra account/billing).
# Takes the user-facing PR *titles* (area:desktop / area:backend) and asks the model
# to rewrite them as a few friendly, jargon-free one-liners for the in-app "What's
# New" splash and the top of the release page.
#
# BEST-EFFORT BY DESIGN: prints nothing and exits 0 on any problem — no token, no
# user-facing PRs, API error, or empty/garbage output. The caller then just ships
# the plain changelog, so a release never depends on the LLM.
#
# Requires: git, gh, jq, curl. GH_TOKEN with `models: read` (the workflow grants it
# to the built-in GITHUB_TOKEN) + repo read for `gh pr view`.
#
# POSIX-bash (no mapfile / associative arrays) so it runs on the macOS runners'
# stock bash 3.2.

set -uo pipefail

RANGE="${1:-}"
[ -z "$RANGE" ] && exit 0

MODEL="${HIGHLIGHTS_MODEL:-openai/gpt-4o-mini}"
TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
[ -z "$TOKEN" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0
command -v curl >/dev/null 2>&1 || exit 0

# Collect user-facing PR titles (desktop + backend), one per line.
titles=""
while IFS= read -r subject; do
  n=$(printf '%s' "$subject" | grep -oE '\(#[0-9]+\)$' | tr -d '()#' || true)
  [ -z "$n" ] && continue
  data=$(gh pr view "$n" --json title,labels 2>/dev/null) || continue
  facing=$(printf '%s' "$data" \
    | jq -r '[.labels[].name] | map(select(. == "area:desktop" or . == "area:backend")) | length')
  [ "${facing:-0}" -eq 0 ] && continue
  t=$(printf '%s' "$data" | jq -r '.title')
  titles="${titles}- ${t}"$'\n'
done <<< "$(git log --reverse --format='%s' "$RANGE" 2>/dev/null || true)"

[ -z "$titles" ] && exit 0   # nothing user-facing → no highlights

SYS="You write release highlights for Crisp, a Mac app that removes silent pauses and filler words from videos. Rewrite the given pull-request titles as 3 to 5 short, friendly, user-facing bullet points a non-technical user would understand. Rules: no jargon, no PR numbers, no author names, no headers, no preamble. One short line each, starting with '- '. Combine closely related items. Output only the bullet lines."

payload=$(jq -n --arg model "$MODEL" --arg sys "$SYS" --arg user "$titles" \
  '{model: $model, temperature: 0.3,
    messages: [{role:"system", content:$sys}, {role:"user", content:$user}]}') || exit 0

resp=$(curl -sS --max-time 30 \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  "https://models.github.ai/inference/chat/completions" \
  -d "$payload" 2>/dev/null) || exit 0

content=$(printf '%s' "$resp" | jq -r '.choices[0].message.content // empty' 2>/dev/null || true)
[ -z "$content" ] && exit 0

# Keep only bullet lines, normalize the marker, cap at 5 — defends against the model
# adding a preamble, numbering, or going long.
bullets=$(printf '%s\n' "$content" \
  | grep -E '^[[:space:]]*[-*•] ' \
  | sed -E 's/^[[:space:]]*[-*•][[:space:]]+/- /' \
  | head -5 || true)
[ -z "$bullets" ] && exit 0

echo "## Highlights"
echo
printf '%s\n' "$bullets"
echo
