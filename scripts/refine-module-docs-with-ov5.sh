#!/usr/bin/env bash
# refine-module-docs-with-ov5.sh — Use OV5 ontology and AutoTTS to refine module docs

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODULES_DIR="$DIR/mementum/knowledge/modules"
LISP_DIR="$DIR/lisp/modules"
PLAN_DIR="$DIR/plans/refine-module-docs-with-ov5-ontology"

# Create plan directories if they don't exist
mkdir -p "$PLAN_DIR"/{phases,implementation,handovers}

echo "[refine-docs] Using OV5 ontology and AutoTTS to refine module docs..."
echo "[refine-docs] Modules dir: $MODULES_DIR"
echo "[refine-docs] Lisp dir: $LISP_DIR"

# Get list of already refined modules (first 20)
REFINED_MODULES=(
  "gptel-auto-workflow-evolution.md"
  "gptel-auto-workflow-production.md"
  "gptel-tools-agent-base.md"
  "gptel-tools-agent-main.md"
  "gptel-tools.md"
  "gptel-tools-edit.md"
  "gptel-tools-bash.md"
  "gptel-tools-grep.md"
  "gptel-auto-workflow-bootstrap.md"
  "gptel-auto-workflow-strategic.md"
  "gptel-auto-workflow-mementum.md"
  "gptel-auto-workflow-knowledge-reasoning.md"
  "gptel-auto-workflow-skill-governance.md"
  "gptel-tools-agent-prompt-build.md"
  "gptel-tools-agent-strategy-harness.md"
  "gptel-tools-agent-experiment-core.md"
  "gptel-tools-agent-worktree.md"
  "gptel-ext-security.md"
  "gptel-sandbox.md"
  "nucleus-tools.md"
)

echo "[refine-docs] Already refined: ${#REFINED_MODULES[@]} modules"

# Get list of remaining modules
ALL_MODULES=($(ls "$MODULES_DIR"/*.md 2>/dev/null | xargs -n1 basename))
REMAINING_MODULES=()
for module in "${ALL_MODULES[@]}"; do
  if [[ ! " ${REFINED_MODULES[@]} " =~ " ${module} " ]]; then
    REMAINING_MODULES+=("$module")
  fi
done

echo "[refine-docs] Remaining to refine: ${#REMAINING_MODULES[@]} modules"

# Process each remaining module
for module in "${REMAINING_MODULES[@]}"; do
  echo "[refine-docs] Processing: $module"
  
  # Get source file name (replace .md with .el)
  source_file="${module%.md}.el"
  source_path="$LISP_DIR/$source_file"
  
  # Check if source file exists
  if [[ ! -f "$source_path" ]]; then
    echo "[refine-docs]   Source not found: $source_path (skipping)"
    continue
  fi
  
  echo "[refine-docs]   Source: $source_path"
  
  # TODO: Use OV5 ontology to categorize
  # TODO: Use AutoTTS to generate description
  # TODO: Apply patterns (nil-guard, string-guard)
  
  echo "[refine-docs]   Done: $module"
done

echo "[refine-docs] Complete!"
