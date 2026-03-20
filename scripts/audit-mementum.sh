#!/bin/bash
#
# Audit mementum for noise memories and stale references.
# Run: ./scripts/audit-mementum.sh
#
# Exit codes:
#   0 - No issues found
#   1 - Noise memories detected
#   2 - Stale references found
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
MEMORIES_DIR="$PROJECT_ROOT/mementum/memories"
KNOWLEDGE_DIR="$PROJECT_ROOT/mementum/knowledge"
ISSUES=0

echo "=== Mementum Audit ==="
echo ""

# Check for noise memories
echo "Checking for noise memories..."
NOISE_FILES=$(grep -l -E "(0 issues.*0 improvements|0 anti-patterns.*0 improvements|Observed 0.*applied 0|0 → 0 → 0)" "$MEMORIES_DIR"/*.md 2>/dev/null || true)

if [ -n "$NOISE_FILES" ]; then
    echo "❌ Found noise memories:"
    echo "$NOISE_FILES" | while read -r file; do
        echo "  - $(basename "$file")"
    done
    ISSUES=1
else
    echo "✓ No noise memories found"
fi

# Check for stale references in knowledge files
echo ""
echo "Checking for stale references in knowledge files..."
for file in "$KNOWLEDGE_DIR"/*.md; do
    if [ -f "$file" ]; then
        # Extract related: references
        RELATED=$(grep -E "^related:|^  - " "$file" 2>/dev/null | grep -oE "mementum/[a-zA-Z0-9/_-]+\.md" || true)
        for ref in $RELATED; do
            REF_PATH="$PROJECT_ROOT/$ref"
            if [ ! -f "$REF_PATH" ]; then
                echo "❌ Stale reference in $(basename "$file"): $ref"
                ISSUES=2
            fi
        done
    fi
done

if [ $ISSUES -eq 0 ]; then
    echo "✓ No stale references found"
fi

echo ""
if [ $ISSUES -eq 0 ]; then
    echo "✓ Mementum audit passed"
    exit 0
else
    echo "❌ Mementum audit failed with issues"
    exit $ISSUES
fi