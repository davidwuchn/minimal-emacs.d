#!/usr/bin/env bash
# run-pipeline-ops.sh — Pipeline + OPS Integration Wrapper
# Calls OPS skills before/after pipeline execution

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PIPELINE_SCRIPT="$DIR/scripts/run-pipeline.sh"
PLANS_DIR="$DIR/mementum/knowledge/plans/pipeline-runs"
DATE=$(date '+%Y-%m-%d')
TIMESTAMP=$(date '+%Y%m%d-%H%M%S')

mkdir -p "$PLANS_DIR"

# ─── Step 1: Create Plan ───
# echo "[pipeline-ops] Creating plan..."
# mkdir -p "$PLANS_DIR/run-$TIMESTAMP"
# cat > "$PLANS_DIR/run-$TIMESTAMP/plan.md" <<EOF
# Pipeline Run $TIMESTAMP

## Objective
Run OV5 self-evolution pipeline with research → digestion → workflow.

## Requirements
- Research findings digested before workflow
- Quota-aware scheduling
- Results tracked in mementum

## DoD
- [ ] Pipeline completes without error
- [ ] Results stored in mementum/memories/
- [ ] State updated in mementum/state.md

## Changelog
- **$DATE**: Plan created
EOF

# ─── Step 2: Run Pipeline ───
echo "[pipeline-ops] Running pipeline..."
if "$PIPELINE_SCRIPT" "$@"; then
    STATUS="success"
    echo "[pipeline-ops] Pipeline succeeded"
else
    STATUS="failure"
    echo "[pipeline-ops] Pipeline failed"
fi

# ─── Step 3: Update Plan ───
# echo "[pipeline-ops] Updating plan..."
# cat >> "$PLANS_DIR/run-$TIMESTAMP/plan.md" <<EOF

## Results

- **Status**: $STATUS
- **Timestamp**: $TIMESTAMP

EOF

# ─── Step 4: Update Mementum State ───
echo "[pipeline-ops] Updating mementum/state.md..."
if [ -f "$DIR/mementum/state.md" ]; then
    # Prepend pipeline run to state
    TMP=$(mktemp)
    {
        echo "# Mementum State"
        echo ""
        echo "> Last pipeline: $DATE ($STATUS)"
        echo "> Next pipeline: scheduled"
        echo ""
        echo "## Latest Pipeline Run"
        echo ""
        echo "- **Date**: $DATE"
        echo "- **Status**: $STATUS"
        echo "- **Plan**: $PLANS_DIR/run-$TIMESTAMP/"
        echo ""
        # Append rest of existing state (skip first line)
        tail -n +2 "$DIR/mementum/state.md" 2>/dev/null || true
    } > "$TMP"
    mv "$TMP" "$DIR/mementum/state.md"
fi

echo "[pipeline-ops] Done. Plan: $PLANS_DIR/run-$TIMESTAMP/"
