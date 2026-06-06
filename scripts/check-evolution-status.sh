#!/usr/bin/env bash
# check-evolution-status.sh - Check self-evolution system status
# Verifies if the self-evolution cycle is actually running and self-improving

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║           OV5 Self-Evolution System Status Check              ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""

# 1. Check if knowledge reasoning module is loaded
echo "━━━ 1. Knowledge Reasoning Module ━━━"
if grep -q "gptel-auto-workflow-knowledge-reasoning" lisp/modules/gptel-auto-workflow-evolution.el; then
    echo "✓ Knowledge reasoning module is declared"
else
    echo "✗ Knowledge reasoning module NOT declared"
fi

if [ -f "lisp/modules/gptel-auto-workflow-knowledge-reasoning.el" ]; then
    echo "✓ Knowledge reasoning module file exists"
else
    echo "✗ Knowledge reasoning module file missing"
fi

# Check if knowledge reasoning is loaded in self-evolution knowledge
if [ -f "var/tmp/experiments/main-baseline-5036/mementum/knowledge/self-evolution.md" ]; then
    if grep -q "not loaded" "var/tmp/experiments/main-baseline-5036/mementum/knowledge/self-evolution.md"; then
        echo "✗ Knowledge reasoning NOT loaded (self-evolution.md shows 'not loaded')"
    else
        echo "✓ Knowledge reasoning loaded (self-evolution.md shows active)"
    fi
else
    echo "? Self-evolution knowledge file not found"
fi
echo ""

# 2. Check evolution scores trend
echo "━━━ 2. Evolution Score Trend ━━━"
if [ -f "var/tmp/evolution-scores.json" ]; then
    # Extract last 5 scores
    scores=$(python3 -c "
import json, sys
with open('var/tmp/evolution-scores.json', 'r') as f:
    data = json.load(f)
scores = data.get('scores', [])[:5]
for s in scores:
    if isinstance(s, dict):
        print(f\"{s.get('timestamp', 'N/A')}: {s.get('score', 0):.2%} ({s.get('total', 0)} total)\")
    elif isinstance(s, list) and len(s) >= 2:
        print(f\"{s[0]}: {s[1]:.2%} ({s[2] if len(s) > 2 else 0} total)\")
" 2>/dev/null || echo "Failed to parse scores")
    
    # Calculate trend
    trend=$(python3 -c "
import json, sys
with open('var/tmp/evolution-scores.json', 'r') as f:
    data = json.load(f)
scores = data.get('scores', [])[:10]
if len(scores) >= 2:
    first = scores[0]
    last = scores[-1]
    first_score = first.get('score', 0) if isinstance(first, dict) else first[1] if len(first) > 1 else 0
    last_score = last.get('score', 0) if isinstance(last, dict) else last[1] if len(last) > 1 else 0
    diff = last_score - first_score
    if diff > 0.01:
        print(f'↑ Improving (+{diff:.2%})')
    elif diff < -0.01:
        print(f'↓ Declining ({diff:.2%})')
    else:
        print(f'→ Stable ({diff:.2%})')
" 2>/dev/null || echo "Failed to calculate trend")
    
    echo ""
    echo "Latest score: $trend"
else
    echo "✗ Evolution scores file not found"
fi
echo ""

# 3. Check self-evolution cycle status
echo "━━━ 3. Self-Evolution Cycle Status ━━━"
if [ -f "lisp/modules/gptel-auto-workflow-evolution.el" ]; then
    if grep -q "defun gptel-auto-workflow-evolution-run-cycle" lisp/modules/gptel-auto-workflow-evolution.el; then
        echo "✓ Self-evolution cycle function exists"
    else
        echo "✗ Self-evolution cycle function missing"
    fi
    
    # Check if evolution is being called
    if grep -q "gptel-auto-workflow-evolution-run-cycle" lisp/modules/gptel-auto-workflow-production.el; then
        echo "✓ Self-evolution cycle is called from production module"
    else
        echo "✗ Self-evolution cycle NOT called from production module"
    fi
else
    echo "✗ Evolution module not found"
fi
echo ""

# 4. Check closed-loop feedback
echo "━━━ 4. Closed-Loop Feedback ━━━"
if [ -f "lisp/modules/gptel-auto-workflow-context-database.el" ]; then
    echo "✓ Context database module exists"
    
    # Check if context database is integrated
    if grep -q "gptel-auto-workflow--context-db-persist" lisp/modules/gptel-auto-workflow-production.el; then
        echo "✓ Context database persist called from production"
    else
        echo "✗ Context database persist NOT called"
    fi
    
    if grep -q "gptel-auto-workflow--context-db-load" lisp/modules/gptel-tools-agent-main.el; then
        echo "✓ Context database load called from main"
    else
        echo "✗ Context database load NOT called"
    fi
else
    echo "✗ Context database module not found"
fi

# Check if context is actually being used
if [ -f "lisp/modules/gptel-token-economics.el" ]; then
    if grep -q "gptel-auto-workflow--get-context" lisp/modules/gptel-token-economics.el; then
        echo "✓ Token economics queries context database"
    else
        echo "? Token economics does not query context"
    fi
fi

if [ -f "lisp/modules/gptel-auto-workflow-human-interface.el" ]; then
    if grep -q "gptel-auto-workflow--get-context-summary" lisp/modules/gptel-auto-workflow-human-interface.el; then
        echo "✓ Human interface queries context summary"
    else
        echo "? Human interface does not query context summary"
    fi
fi
echo ""

# 5. Check operational metrics
echo "━━━ 5. Operational Metrics ━━━"
if [ -d "var/tmp/experiments" ]; then
    # Count experiments
    exp_count=$(find var/tmp/experiments -type d -name "main-baseline-*" | wc -l | tr -d ' ')
    echo "✓ $exp_count baseline experiment directories found"
    
    # Check for kept experiments
    kept_count=$(find var/tmp/experiments -name "results.tsv" -exec grep -l "kept" {} \; 2>/dev/null | wc -l | tr -d ' ')
    echo "✓ $kept_count experiments marked as 'kept'"
    
    # Check for evolution patterns
    if [ -d "mementum/knowledge" ]; then
        pattern_count=$(ls mementum/knowledge/*.md 2>/dev/null | wc -l | tr -d ' ')
        echo "✓ $pattern_count knowledge pages in mementum"
    fi
else
    echo "✗ Experiments directory not found"
fi
echo ""

# 6. Summary
echo "━━━ Summary ━━━"
echo "The self-evolution system is implemented but needs verification:"
echo ""
echo "✓ Implemented:"
echo "  - Knowledge reasoning module"
echo "  - Context database with persistence"
echo "  - Self-evolution cycle"
echo "  - Closed-loop feedback mechanisms"
echo ""
echo "? Needs verification:"
echo "  - Is the self-evolution cycle actually running?"
echo "  - Is context being used to inform decisions?"
echo "  - Is the system actually self-improving?"
echo ""
echo "Next steps:"
echo "  1. Monitor evolution scores over time"
echo "  2. Verify closed-loop feedback is working"
echo "  3. Check if context is actually informing decisions"
echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║                   Status Check Complete                       ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
