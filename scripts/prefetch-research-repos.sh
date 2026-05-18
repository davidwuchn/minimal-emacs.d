#!/usr/bin/env bash
# Pre-fetch deep content from priority research repos using gh.
# Goes beyond top-level docs — fetches architecture, source code, and varied files.
# Outputs markdown suitable for injection into researcher subagent prompt.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT="${1:-$DIR/var/tmp/prefetched-research.md}"
MAX_REPOS="${MAX_RESEARCH_FETCH:-17}"

mkdir -p "$(dirname "$OUTPUT")"

# Repo → deep files to try (ordered by priority)
# First file found wins. Empty means "try default AGENTS.md/README.md only"
declare -A REPO_FILES
REPO_FILES[davidwuchn/nucleus]="COMPILER.md DEBUGGER.md LAMBDA-COMPILER.md ALLIUM.md BEHAVIORS.md VSM.md VSM_FIVE.md SYSTEM_DESIGN.md PHILOSOPHY_RESEARCH.md SYMBOLIC_FRAMEWORK.md"
REPO_FILES[davidwuchn/mementum]="mementum/knowledge/project-facts.md mementum/knowledge/patterns.md mementum/knowledge/planning-protocol.md"
REPO_FILES[davidwuchn/semantica]="semantica/ontology/ontology_generator.py semantica/context/context_graph.py semantica/context/decision_models.py"
REPO_FILES[davidwuchn/genesis-agent]="genesis/agent.py genesis/memory.py genesis/tools.py"
REPO_FILES[davidwuchn/GitNexus]="gitnexus/core.py gitnexus/graph.py"
REPO_FILES[davidwuchn/LLMLingua]="llmlingua/prompt_compressor.py"
REPO_FILES[davidwuchn/ATLAS]="atlas/retrieval.py atlas/embedding.py"
REPO_FILES[davidwuchn/psi]="psi/collapse.py psi/engine.py"
REPO_FILES[davidwuchn/mycelium]="mycelium/network.py mycelium/node.py"
REPO_FILES[davidwuchn/Aether]="aether/stream.py aether/transform.py"

# Repos without specific deep files — fetch default AGENTS.md/INTRO.md/README.md
REPOS=(
  "davidwuchn/nucleus"
  "davidwuchn/mementum"
  "davidwuchn/semantica"
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

fetch_file() {
  local repo="$1" file="$2" max_lines="${3:-300}"
  gh api "repos/$repo/contents/$file" --jq '.content' 2>/dev/null | base64 -d 2>/dev/null | head -"$max_lines" || true
}

{
  echo "# Pre-Fetched Repo Analysis"
  echo ""
  echo "> Fetched $(date '+%Y-%m-%d %H:%M') — synthesize actionable techniques from this content."
  echo "> Deep files: architecture docs, source code, protocols — not just surface READMEs."
  echo ""

  count=0
  for repo in "${REPOS[@]}"; do
    [ "$count" -ge "$MAX_REPOS" ] && break
    echo "## $repo"
    echo ""

    content=""
    # Try deep files first — rotate which one is picked based on day-of-year
    deep_files="${REPO_FILES[$repo]:-}"
    if [ -n "$deep_files" ]; then
      # Convert space-separated list to array, pick index based on date for variety
      IFS=' ' read -ra deep_arr <<< "$deep_files"
      day_of_year=$(date +%j)
      start_idx=$(( day_of_year % ${#deep_arr[@]} ))  # rotate daily
      # Try from rotated start, wrapping around
      for ((i=0; i<${#deep_arr[@]}; i++)); do
        idx=$(( (start_idx + i) % ${#deep_arr[@]} ))
        file="${deep_arr[$idx]}"
        content=$(fetch_file "$repo" "$file" 300)
        if [ -n "$content" ] && [ "$(echo "$content" | wc -l)" -gt 5 ]; then
          echo "$content"
          echo ""
          echo "  [fetched $repo/$file (deep, idx=$idx): $(echo "$content" | wc -c)B]" >&2
          break
        fi
      done
    fi

    # Fallback: surface docs
    if [ -z "$content" ] || [ "$(echo "$content" | wc -l)" -le 5 ]; then
      for file in AGENTS.md INTRO.md README.md; do
        content=$(fetch_file "$repo" "$file" 200)
        if [ -n "$content" ] && [ "$(echo "$content" | wc -l)" -gt 3 ]; then
          echo "$content"
          echo ""
          echo "  [fetched $repo/$file (surface): $(echo "$content" | wc -c)B]" >&2
          break
        fi
      done
    fi

    if [ -z "${content:-}" ] || [ "$(echo "${content:-}" | wc -l)" -le 3 ]; then
      echo "_Could not fetch $repo_"
    fi
    echo ""
    count=$((count + 1))
  done
} > "$OUTPUT"

echo "Prefetched $count repos → $OUTPUT ($(wc -c < "$OUTPUT")B)" >&2
