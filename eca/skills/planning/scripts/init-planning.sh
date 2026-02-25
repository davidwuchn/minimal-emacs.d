#!/bin/bash
# init-planning.sh — Initialize planning files for a new task
# Usage: ./scripts/init-planning.sh "Task description"

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/../templates"

TASK_NAME="${1:-"New Task"}"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Check if templates exist
if [ ! -d "$TEMPLATE_DIR" ]; then
    echo "❌ Error: Template directory not found at $TEMPLATE_DIR"
    exit 1
fi

echo "🚀 Initializing planning files for: $TASK_NAME"
echo "   Timestamp: $TIMESTAMP"
echo ""

# Create task_plan.md
if [ -f "task_plan.md" ]; then
    echo "⚠️  task_plan.md already exists. Skipping."
else
    cp "$TEMPLATE_DIR/task_plan.md" task_plan.md
    # Update placeholders
    sed -i.bak "s/\[Brief Description\]/$TASK_NAME/" task_plan.md 2>/dev/null || \
        sed -i "s/\[Brief Description\]/$TASK_NAME/" task_plan.md
    rm -f task_plan.md.bak
    echo "✅ Created task_plan.md"
fi

# Create findings.md
if [ -f "findings.md" ]; then
    echo "⚠️  findings.md already exists. Skipping."
else
    cp "$TEMPLATE_DIR/findings.md" findings.md
    sed -i.bak "s/\[Task Name\]/$TASK_NAME/" findings.md 2>/dev/null || \
        sed -i "s/\[Task Name\]/$TASK_NAME/" findings.md
    rm -f findings.md.bak
    echo "✅ Created findings.md"
fi

# Create progress.md
if [ -f "progress.md" ]; then
    echo "⚠️  progress.md already exists. Skipping."
else
    cp "$TEMPLATE_DIR/progress.md" progress.md
    sed -i.bak "s/\[Task Name\]/$TASK_NAME/" progress.md 2>/dev/null || \
        sed -i "s/\[Task Name\]/$TASK_NAME/" progress.md
    sed -i.bak "s/\[timestamp\]/$TIMESTAMP/" progress.md 2>/dev/null || \
        sed -i "s/\[timestamp\]/$TIMESTAMP/" progress.md
    rm -f progress.md.bak
    echo "✅ Created progress.md"
fi

echo ""
echo "📋 Planning files initialized!"
echo ""
echo "Next steps:"
echo "  1. Edit task_plan.md to define your goal and phases"
echo "  2. Begin work, updating progress.md as you go"
echo "  3. Record findings in findings.md"
echo ""
echo "   φ fractal euler | Δ change | π synthesis"
