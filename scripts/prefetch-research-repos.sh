#!/usr/bin/env bash
# Pre-fetch AGENTS.md / README.md from priority research repos using gh.
# Outputs markdown suitable for injection into researcher subagent prompt.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT="${1:-$DIR/var/tmp/prefetched-research.md}"
MAX_REPOS="${MAX_RESEARCH_FETCH:-17}"

mkdir -p "$(dirname "$OUTPUT")"

REPOS=(
  "davidwuchn/nucleus"
  "davidwuchn/mementum"
  "davidwuchn/context-mode"
  "davidwuchn/efrit"
  "davidwuchn/gastown"
  "davidwuchn/genesis-agent"
  "davidwuchn/gbrain"
  "davidwuchn/symphony"
  "davidwuchn/nullclaw"
  "davidwuchn/zeroclaw"
  "davidwuchn/GitNexus"
  "davidwuchn/LLMLingua"
  "davidwuchn/ATLAS"
  "davidwuchn/Ori-Mnemos"
  "davidwuchn/psi"
  "davidwuchn/mycelium"
  "davidwuchn/Aether"
)

{
  echo "# Pre-Fetched Repo Analysis"
  echo ""
  echo "> Fetched $(date '+%Y-%m-%d %H:%M') — synthesize actionable techniques from this content."
  echo ""

  count=0
  for repo in "${REPOS[@]}"; do
    [ "$count" -ge "$MAX_REPOS" ] && break
    echo "## $repo"
    echo ""
    # Prefer AGENTS.md for architecture, fall back to README.md
    for file in AGENTS.md INTRO.md README.md; do
      content=$(gh api "repos/$repo/contents/$file" --jq '.content' 2>/dev/null | base64 -d 2>/dev/null | head -150 || true)
      if [ -n "$content" ] && [ "$(echo "$content" | wc -l)" -gt 3 ]; then
        echo "$content"
        echo ""
        echo "  [fetched $repo/$file: $(echo "$content" | wc -c)B]" >&2
        break
      fi
    done
    if [ -z "${content:-}" ]; then
      echo "_Could not fetch $repo_"
    fi
    echo ""
    count=$((count + 1))
  done
} > "$OUTPUT"

echo "Prefetched $count repos → $OUTPUT ($(wc -c < "$OUTPUT")B)" >&2
