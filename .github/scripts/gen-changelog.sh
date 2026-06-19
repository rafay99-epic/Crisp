#!/usr/bin/env bash
#
# gen-changelog.sh <git-range>
#
# Emit Markdown release notes for the squash-merged PRs in <git-range>, grouped by
# the `area:*` label the labeler workflow applies — the same grouping the weekly
# promotion PR uses. Shared by:
#   • promotion.sh  — the nightly → main promotion PR body
#   • ci.yml        — the Stable release notes (PRs since the last promotion)
#   • nightly.yml   — the Nightly pre-release notes (PRs since the last build)
#
# <git-range> is anything `git log` accepts (e.g. `origin/main..HEAD`, `A..B`). The
# commits must be reachable (callers fetch `nightly` and check out full history).
#
# Requires: git, gh, jq. GH_TOKEN with repo read (for `gh pr view` labels/author).
# Prints only the grouped sections — callers add their own header/footer. Empty
# range → no output (callers treat that as "fall back" / "nothing to list").
#
# Deliberately POSIX-bash (no `mapfile` / associative arrays) so it runs on the
# macOS runners' stock bash 3.2 as well as Linux.

set -euo pipefail

RANGE="${1:?usage: gen-changelog.sh <git-range>}"

bucket_desktop=""; bucket_website=""; bucket_backend=""
bucket_ci=""; bucket_docs=""; bucket_uncat=""
count_desktop=0; count_website=0; count_backend=0
count_ci=0; count_docs=0; count_uncat=0

# Squash-merged PRs end every subject with `(#NN)`. `--reverse` so the oldest lands
# first, matching merge order into nightly.
subjects=$(git log --reverse --format='%s' "$RANGE" || true)
while IFS= read -r subject; do
  n=$(printf '%s' "$subject" | grep -oE '\(#[0-9]+\)$' | tr -d '()#' || true)
  [ -z "$n" ] && continue
  data=$(gh pr view "$n" --json title,author,labels 2>/dev/null) \
    || { echo "skip #$n (gh pr view failed)" >&2; continue; }
  title=$(printf '%s' "$data" | jq -r '.title')
  author=$(printf '%s' "$data" | jq -r '.author.login // "ghost"')
  areas=$(printf '%s' "$data" | jq -r '.labels[].name' | grep '^area:' | sed 's/^area://' || true)

  line="- #${n} ${title} — @${author}"

  # Assign each PR to exactly ONE bucket, by priority — a PR with several area:*
  # labels (e.g. desktop + docs) must not be duplicated across sections or
  # double-counted in the header counts.
  bucket=""
  for pri in desktop backend website ci docs; do
    if printf '%s\n' "$areas" | grep -qx "$pri"; then bucket="$pri"; break; fi
  done
  case "$bucket" in
    desktop) bucket_desktop="${bucket_desktop}${line}"$'\n'; count_desktop=$((count_desktop + 1)) ;;
    website) bucket_website="${bucket_website}${line}"$'\n'; count_website=$((count_website + 1)) ;;
    backend) bucket_backend="${bucket_backend}${line}"$'\n'; count_backend=$((count_backend + 1)) ;;
    ci)      bucket_ci="${bucket_ci}${line}"$'\n';           count_ci=$((count_ci + 1)) ;;
    docs)    bucket_docs="${bucket_docs}${line}"$'\n';       count_docs=$((count_docs + 1)) ;;
    *)       bucket_uncat="${bucket_uncat}${line}"$'\n';     count_uncat=$((count_uncat + 1)) ;;
  esac
done <<< "$subjects"

# Anything without a `(#NN)` suffix bypassed the PR flow — surface it as a safety net.
direct=$(git log --reverse --format='%h  %s' "$RANGE" | grep -vE '\(#[0-9]+\)$' || true)

emit() {  # <label> <count> <body>
  [ "$2" -eq 0 ] && return
  echo "### $1 ($2)"
  echo
  printf '%s' "$3"
  echo
}

emit "Desktop"       "$count_desktop"  "$bucket_desktop"
emit "Website"       "$count_website"  "$bucket_website"
emit "Backend"       "$count_backend"  "$bucket_backend"
emit "CI"            "$count_ci"       "$bucket_ci"
emit "Docs"          "$count_docs"     "$bucket_docs"
emit "Uncategorized" "$count_uncat"    "$bucket_uncat"

if [ -n "$direct" ]; then
  echo "### Direct commits"
  echo
  echo "Landed without a PR — surfaced as a safety net."
  echo
  echo '```'
  printf '%s\n' "$direct"
  echo '```'
  echo
fi
