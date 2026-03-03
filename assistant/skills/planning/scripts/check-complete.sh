#!/bin/bash
# check-complete.sh — Verify task completion before finishing
# Usage: ./scripts/check-complete.sh

set -e

PLAN_DIR="docs/plans"
ERRORS=0
WARNINGS=0

echo "🔍 Checking task completion..."
echo ""

# Check if planning files exist
echo "📁 Checking planning files..."

if [ -f "$PLAN_DIR/task_plan.md" ]; then
    echo "  ✅ $PLAN_DIR/task_plan.md exists"
else
    echo "  ❌ $PLAN_DIR/task_plan.md missing"
    ((ERRORS++))
fi

if [ -f "$PLAN_DIR/findings.md" ]; then
    echo "  ✅ $PLAN_DIR/findings.md exists"
else
    echo "  ⚠️  $PLAN_DIR/findings.md missing (optional but recommended)"
    ((WARNINGS++))
fi

if [ -f "$PLAN_DIR/progress.md" ]; then
    echo "  ✅ $PLAN_DIR/progress.md exists"
else
    echo "  ⚠️  $PLAN_DIR/progress.md missing (optional but recommended)"
    ((WARNINGS++))
fi

echo ""

# Check task_plan.md for completion
if [ -f "$PLAN_DIR/task_plan.md" ]; then
    echo "📋 Checking $PLAN_DIR/task_plan.md..."
    
    # Check for incomplete phases
    INCOMPLETE=$(grep -c "Status:.*\`pending\`" "$PLAN_DIR/task_plan.md" 2>/dev/null || echo "0")
    IN_PROGRESS=$(grep -c "Status:.*\`in_progress\`" "$PLAN_DIR/task_plan.md" 2>/dev/null || echo "0")
    
    if [ "$INCOMPLETE" -gt 0 ]; then
        echo "  ⚠️  $INCOMPLETE phase(s) still pending"
        ((WARNINGS++))
    fi
    
    if [ "$IN_PROGRESS" -gt 0 ]; then
        echo "  ⚠️  $IN_PROGRESS phase(s) still in progress"
        ((WARNINGS++))
    fi
    
    # Check if goal is defined
    if grep -q "\[One sentence describing the end state\]" "$PLAN_DIR/task_plan.md"; then
        echo "  ⚠️  Goal not defined (placeholder still present)"
        ((WARNINGS++))
    else
        echo "  ✅ Goal defined"
    fi
fi

echo ""

# Check for uncommitted changes
echo "📝 Checking git status..."
if git rev-parse --git-dir > /dev/null 2>&1; then
    UNCOMMITTED=$(git status --porcelain 2>/dev/null | wc -l)
    if [ "$UNCOMMITTED" -gt 0 ]; then
        echo "  ⚠️  $UNCOMMITTED uncommitted change(s)"
        git status --short
        ((WARNINGS++))
    else
        echo "  ✅ Working directory clean"
    fi
else
    echo "  ℹ️  Not a git repository"
fi

echo ""

# Summary
echo "═══════════════════════════════════════"
if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo "✅ All checks passed! Task appears complete."
    echo ""
    echo "φ fractal euler | π synthesis | Δ complete"
    exit 0
elif [ $ERRORS -eq 0 ]; then
    echo "⚠️  $WARNINGS warning(s) found. Review before finishing."
    exit 0
else
    echo "❌ $ERRORS error(s), $WARNINGS warning(s) found."
    echo "   Address errors before completing task."
    exit 1
fi
