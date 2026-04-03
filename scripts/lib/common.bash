# scripts/lib/common.bash - Common functions for Emacs.d scripts
#
# Source this file from other scripts:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/common.bash"
#
# Provides:
#   - DIR resolution
#   - Color codes
#   - pass/fail/skip/section functions
#   - resolve_emacsclient / resolve_emacs
#   - run_batch_bootstrap
#   - lisp_escape

# ═══════════════════════════════════════════════════════════════════════════
# Directory Resolution
# ═══════════════════════════════════════════════════════════════════════════

# The library is at scripts/lib/common.bash
# Go up 2 levels: scripts/lib -> scripts -> repo root
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIR="$(cd "$_LIB_DIR/../.." && pwd)"
unset _LIB_DIR

# ═══════════════════════════════════════════════════════════════════════════
# Colors
# ═══════════════════════════════════════════════════════════════════════════

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ═══════════════════════════════════════════════════════════════════════════
# Test Helpers
# ═══════════════════════════════════════════════════════════════════════════

PASS=0
FAIL=0
SKIP=0

pass() { echo -e "${GREEN}✓${NC} $1"; PASS=$((PASS + 1)); }
fail() { echo -e "${RED}✗${NC} $1"; FAIL=$((FAIL + 1)); }
skip() { echo -e "${YELLOW}○${NC} $1"; SKIP=$((SKIP + 1)); }
section() { echo ""; echo "=== $1 ==="; }

reset_counters() { PASS=0; FAIL=0; SKIP=0; }

print_summary() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo -e "Summary: ${GREEN}PASS: $PASS${NC} ${RED}FAIL: $FAIL${NC} ${YELLOW}SKIP: $SKIP${NC}"
    echo "═══════════════════════════════════════════════════════════════"
}

# ═══════════════════════════════════════════════════════════════════════════
# Emacs Resolution
# ═══════════════════════════════════════════════════════════════════════════

resolve_emacsclient() {
    if command -v emacsclient >/dev/null 2>&1; then
        command -v emacsclient
        return
    fi
    if [ -x /opt/homebrew/bin/emacsclient ]; then
        echo /opt/homebrew/bin/emacsclient
        return
    fi
    if [ -x /usr/local/bin/emacsclient ]; then
        echo /usr/local/bin/emacsclient
        return
    fi
    return 1
}

resolve_emacs() {
    if command -v emacs >/dev/null 2>&1; then
        command -v emacs
        return
    fi
    if [ -x /opt/homebrew/bin/emacs ]; then
        echo /opt/homebrew/bin/emacs
        return
    fi
    if [ -x /usr/local/bin/emacs ]; then
        echo /usr/local/bin/emacs
        return
    fi
    if [ -x /Applications/Emacs.app/Contents/MacOS/Emacs ]; then
        echo /Applications/Emacs.app/Contents/MacOS/Emacs
        return
    fi
    return 1
}

# Require emacsclient, exit with error if not found
require_emacsclient() {
    local EMACSCLIENT
    EMACSCLIENT="$(resolve_emacsclient)" || {
        echo "emacsclient not found" >&2
        exit 1
    }
    echo "$EMACSCLIENT"
}

# Require emacs, exit with error if not found
require_emacs() {
    local EMACS
    EMACS="$(resolve_emacs)" || {
        echo "emacs not found" >&2
        exit 1
    }
    echo "$EMACS"
}

# ═══════════════════════════════════════════════════════════════════════════
# Batch Bootstrap
# ═══════════════════════════════════════════════════════════════════════════

run_batch_bootstrap() {
    emacs --batch -Q \
        -L "$DIR" \
        -L "$DIR/lisp" \
        -L "$DIR/lisp/modules" \
        -L "$DIR/packages/gptel" \
        -L "$DIR/packages/gptel-agent" \
        -l "$DIR/scripts/test-auto-workflow-batch.el" \
        -f test-auto-workflow-batch-run
}

# ═══════════════════════════════════════════════════════════════════════════
# Lisp String Escaping
# ═══════════════════════════════════════════════════════════════════════════

lisp_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# ═══════════════════════════════════════════════════════════════════════════
# Emacs Load Path Helpers
# ═══════════════════════════════════════════════════════════════════════════

# Standard load paths for Emacs batch operations
EMACS_BATCH_LIBS=(
    "-L" "$DIR"
    "-L" "$DIR/lisp"
    "-L" "$DIR/lisp/modules"
    "-L" "$DIR/packages/gptel"
    "-L" "$DIR/packages/gptel-agent"
)

# Run emacs in batch mode with standard load paths
emacs_batch() {
    emacs --batch -Q "${EMACS_BATCH_LIBS[@]}" "$@"
}

# Run emacsclient eval with timeout
emacsclient_eval() {
    local server_name="${1:-copilot-auto-workflow}"
    local elisp="$2"
    local timeout="${3:-10}"
    local EMACSCLIENT
    
    EMACSCLIENT="$(resolve_emacsclient)" || {
        echo "emacsclient not found" >&2
        return 1
    }
    
    timeout "$timeout" "$EMACSCLIENT" -s "$server_name" --eval "$elisp"
}
