#!/usr/bin/env bash

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$DIR/scripts/run-auto-workflow-cron.sh"
ELISP_LOAD_AGENT=$(printf '(progn (load-file "%s/lisp/modules/gptel-tools-agent.el") t)' "$DIR")
ELISP_CHECK_ENTRYPOINT=$(printf "(progn (load-file \"%s/lisp/modules/gptel-auto-workflow-projects.el\") (fboundp 'gptel-auto-workflow-cron-safe))" "$DIR")
cd "$DIR"

echo "=== Auto-Workflow E2E Test ==="
echo

echo "[1/7] Checking prerequisites..."
if [ ! -x "$RUNNER" ]; then
    echo "  ✗ wrapper missing or not executable: $RUNNER"
    exit 1
fi
echo "  ✓ wrapper exists: $RUNNER"

if ! command -v emacsclient >/dev/null 2>&1 && [ ! -x /opt/homebrew/bin/emacsclient ] && [ ! -x /usr/local/bin/emacsclient ]; then
    echo "  ✗ emacsclient not found"
    exit 1
fi
echo "  ✓ emacsclient is resolvable"

echo
echo "[2/7] Checking Emacs access..."
if "$RUNNER" status >/dev/null 2>&1; then
    echo "  ✓ wrapper can reach Emacs"
else
    echo "  ✗ wrapper status failed"
    exit 1
fi

echo
echo "[3/7] Checking required modules..."
for module in gptel-tools-agent.el gptel-auto-workflow-projects.el gptel-auto-workflow-strategic.el; do
    if [ -f "lisp/modules/$module" ]; then
        echo "  ✓ $module exists"
    else
        echo "  ✗ $module missing"
        exit 1
    fi
done

echo
echo "[4/7] Checking cron configuration..."
if crontab -l 2>/dev/null | grep -Eq '^[0-9*@].*run-auto-workflow-cron\.sh auto-workflow'; then
    echo "  ✓ Auto-workflow cron job installed via wrapper"
    crontab -l | grep -E '^[0-9*@].*run-auto-workflow-cron\.sh auto-workflow' | head -1 | sed 's/^/    /'
else
    echo "  ✗ Wrapper-based auto-workflow cron job not found"
    echo "    Run: ./scripts/install-cron.sh"
    exit 1
fi

echo
echo "[5/7] Checking required directories..."
for dir in var/tmp/cron var/tmp/experiments; do
    if [ -d "$dir" ]; then
        echo "  ✓ $dir exists"
    else
        echo "  ⚠ $dir missing, creating..."
        mkdir -p "$dir"
    fi
done

echo
echo "[6/7] Testing module loading..."
if emacsclient --eval "$ELISP_LOAD_AGENT" >/dev/null 2>&1; then
    echo "  ✓ gptel-tools-agent.el loads successfully"
else
    echo "  ✗ Failed to load gptel-tools-agent.el"
    exit 1
fi

echo
echo "[7/7] Checking workflow entrypoints..."
if emacsclient --eval "$ELISP_CHECK_ENTRYPOINT" 2>/dev/null | grep -q "t"; then
    echo "  ✓ gptel-auto-workflow-cron-safe function exists"
else
    echo "  ✗ gptel-auto-workflow-cron-safe not found"
    exit 1
fi

if "$RUNNER" status | grep -q ':phase'; then
    echo "  ✓ wrapper status returns workflow data"
else
    echo "  ✗ wrapper status did not return workflow data"
    exit 1
fi

echo
echo "=== All E2E Tests Passed ==="
echo
echo "Next steps:"
echo "1. Test manual run: ./scripts/run-auto-workflow-cron.sh auto-workflow"
echo "2. Check logs: tail -f var/tmp/cron/auto-workflow.log"
echo "3. Wait for cron job at next scheduled time"
