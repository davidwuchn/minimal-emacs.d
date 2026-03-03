#!/bin/bash
# init-planning.sh — Initialize planning files for a new task
# Usage: ./scripts/init-planning.sh "Task description"

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/../templates"
PLAN_DIR="docs/plans"

TASK_NAME="${1:-"New Task"}"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Check if templates exist
if [ ! -d "$TEMPLATE_DIR" ]; then
    echo "❌ Error: Template directory not found at $TEMPLATE_DIR"
    exit 1
fi

# Ensure docs/plans/ directory exists
mkdir -p "$PLAN_DIR"

echo "🚀 Initializing planning files for: $TASK_NAME"
echo "   Directory: $PLAN_DIR/"
echo "   Timestamp: $TIMESTAMP"
echo ""

# Create task_plan.md
if [ -f "$PLAN_DIR/task_plan.md" ]; then
    echo "⚠️  $PLAN_DIR/task_plan.md already exists. Skipping."
else
    cp "$TEMPLATE_DIR/task_plan.md" "$PLAN_DIR/task_plan.md"
    # Update placeholders
    sed -i.bak "s/\[Brief Description\]/$TASK_NAME/" "$PLAN_DIR/task_plan.md" 2>/dev/null || \
        sed -i "s/\[Brief Description\]/$TASK_NAME/" "$PLAN_DIR/task_plan.md"
    rm -f "$PLAN_DIR/task_plan.md.bak"
    echo "✅ Created $PLAN_DIR/task_plan.md"
fi

# Create findings.md
if [ -f "$PLAN_DIR/findings.md" ]; then
    echo "⚠️  $PLAN_DIR/findings.md already exists. Skipping."
else
    cp "$TEMPLATE_DIR/findings.md" "$PLAN_DIR/findings.md"
    sed -i.bak "s/\[Task Name\]/$TASK_NAME/" "$PLAN_DIR/findings.md" 2>/dev/null || \
        sed -i "s/\[Task Name\]/$TASK_NAME/" "$PLAN_DIR/findings.md"
    rm -f "$PLAN_DIR/findings.md.bak"
    echo "✅ Created $PLAN_DIR/findings.md"
fi

# Create progress.md
if [ -f "$PLAN_DIR/progress.md" ]; then
    echo "⚠️  $PLAN_DIR/progress.md already exists. Skipping."
else
    cp "$TEMPLATE_DIR/progress.md" "$PLAN_DIR/progress.md"
    sed -i.bak "s/\[Task Name\]/$TASK_NAME/" "$PLAN_DIR/progress.md" 2>/dev/null || \
        sed -i "s/\[Task Name\]/$TASK_NAME/" "$PLAN_DIR/progress.md"
    sed -i.bak "s/\[timestamp\]/$TIMESTAMP/" "$PLAN_DIR/progress.md" 2>/dev/null || \
        sed -i "s/\[timestamp\]/$TIMESTAMP/" "$PLAN_DIR/progress.md"
    rm -f "$PLAN_DIR/progress.md.bak"
    echo "✅ Created $PLAN_DIR/progress.md"
fi

echo ""
echo "📋 Planning files initialized!"
echo ""
echo "Next steps:"
echo "  1. Edit $PLAN_DIR/task_plan.md to define your goal and phases"
echo "  2. Begin work, updating $PLAN_DIR/progress.md as you go"
echo "  3. Record findings in $PLAN_DIR/findings.md"
echo ""
echo "   φ fractal euler | Δ change | π synthesis"
